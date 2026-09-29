#!/usr/bin/env python3
"""Strict signed-helper protocol probe; --self-test checks the probe offline."""

import json
import os
import selectors
import subprocess
import sys
import time


class ProbeFailure(Exception):
    pass

REDACTED_SENTINEL = "[redacted:assigned-secret]"
RAW_SECRET = "anchor-stdio-raw-secret-0123456789"
TOOL_NAMES = {"context." + name for name in ("current_project", "resume", "search",
    "list_artifacts", "get_artifact",
    "list_sessions", "get_session", "get_messages", "list_knowledge", "get_knowledge")}

def require(condition, explanation):
    if not condition:
        raise ProbeFailure(explanation)

class StdioProbe:
    def __init__(self, command, support, timeout):
        self.timeout = timeout
        self.request_id = 0
        self.pending_stdout = b""
        self.stderr = b""
        self.stdout = b""
        self.responses = []
        self.selector = selectors.DefaultSelector()
        self.child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, env={**os.environ,
                                      "ANCHOR_MCP_TEST_SUPPORT_DIRECTORY": support})
        self.selector.register(self.child.stdout, selectors.EVENT_READ, "stdout")
        self.selector.register(self.child.stderr, selectors.EVENT_READ, "stderr")

    def receive(self, deadline):
        remaining = deadline - time.monotonic()
        require(remaining > 0, "Helper timed out")
        events = self.selector.select(remaining)
        require(events, "Helper timed out")
        for key, _ in events:
            chunk = os.read(key.fd, 65536)
            if not chunk:
                self.selector.unregister(key.fileobj)
                continue
            if key.data == "stderr":
                self.stderr += chunk
                require(len(self.stderr) <= 1048576, "Excessive stderr output")
                require(all(secret.encode() not in self.stderr for secret in
                            (REDACTED_SENTINEL, RAW_SECRET)), "Fixture text leaked to stderr")
                continue
            self.stdout += chunk
            require(len(self.stdout) <= 1048576, "Excessive stdout output")
            require(RAW_SECRET.encode() not in self.stdout, "Raw secret leaked to stdout")
            self.pending_stdout += chunk
            while b"\n" in self.pending_stdout:
                line, self.pending_stdout = self.pending_stdout.split(b"\n", 1)
                try:
                    response = json.loads(line)
                except (ValueError, UnicodeError):
                    raise ProbeFailure("stdout contains a non-JSON line") from None
                require(isinstance(response, dict), "stdout line is not a JSON object")
                self.responses.append(response)

    def send(self, method, parameters=None, notification=False):
        request = {"jsonrpc": "2.0", "method": method}
        if parameters is not None:
            request["params"] = parameters
        if not notification:
            self.request_id += 1
            request["id"] = self.request_id
        self.child.stdin.write(json.dumps(request).encode() + b"\n")
        self.child.stdin.flush()
        if notification:
            return None
        deadline = time.monotonic() + self.timeout
        while not self.responses:
            require(self.selector.get_map(), "Helper closed output before replying")
            self.receive(deadline)
        response = self.responses.pop(0)
        require(response.get("jsonrpc") == "2.0" and response.get("id") == self.request_id,
                "Unexpected JSON-RPC response envelope")
        require("error" not in response and isinstance(response.get("result"), dict),
                "Expected a JSON-RPC result")
        return response["result"]

    def tool(self, name, arguments=None, error_code=None):
        response = self.send("tools/call", {"name": name, "arguments": arguments or {}})
        require(response.get("isError", False) is (error_code is not None),
                "Unexpected tool error flag")
        fields = response.get("structuredContent")
        require(isinstance(fields, dict), "Missing structured tool content")
        if error_code:
            require(fields.get("code") == error_code, "Unexpected typed tool error")
        return fields

    def finish(self):
        self.child.stdin.close()
        deadline = time.monotonic() + self.timeout
        while self.selector.get_map():
            self.receive(deadline)
        require(not self.pending_stdout, "Unterminated stdout line")
        require(not self.responses, "Unexpected extra stdout response")
        try:
            status = self.child.wait(timeout=max(0.001, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            raise ProbeFailure("Helper did not exit after stdin closed") from None
        require(status == 0, "Helper exited unsuccessfully")

    def close(self):
        if self.child.poll() is None:
            self.child.kill()
        self.child.wait()
        for stream in (self.child.stdin, self.child.stdout, self.child.stderr):
            stream.close()
        self.selector.close()


def single_record(fields, key):
    records = fields.get(key)
    require(isinstance(records, list) and len(records) == 1 and isinstance(records[0], dict),
            "Expected exactly one fixture record within the requested limit")
    return records[0]


def verify_protocol(command, workspace, support, timeout=10):
    probe = StdioProbe(command, support, timeout)
    try:
        initialization = probe.send("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "anchor-stdio-verifier", "version": "1.0.0"}})
        require(initialization.get("protocolVersion") == "2025-11-25",
                "Unexpected negotiated protocol version")
        require(initialization.get("serverInfo", {}).get("name") == "anchor",
                "Unexpected server identity")
        probe.send("notifications/initialized", notification=True)
        tools = probe.send("tools/list").get("tools")
        require(isinstance(tools, list) and len(tools) == 10
                and {entry.get("name") for entry in tools} == TOOL_NAMES,
                "Expected exactly the ten context tools")
        project = probe.tool("context.current_project")
        require(project.get("name") == "anchor-stdio-fixture" and project.get("project_id")
                and isinstance(project.get("workspace_path"), str)
                and os.path.realpath(project["workspace_path"]) == os.path.realpath(workspace),
                "Missing fixture project evidence")
        hit = single_record(probe.tool("context.search", {"text": "checkpoint", "limit": 1}), "hits")
        require("checkpoint" in hit.get("excerpt", "") and hit.get("provider") == "codex",
                "Missing fixture search evidence")
        artifact = single_record(probe.tool("context.list_artifacts", {"limit": 1}), "artifacts")
        require(artifact.get("name") == "stdio-latest-note.md" and artifact.get("artifact_id"),
                "Missing fixture artifact evidence")
        probe.tool("context.get_artifact", {"artifact_id": artifact["artifact_id"], "byte_limit": 32},
                   error_code="context_unavailable")
        session = single_record(probe.tool("context.list_sessions", {"limit": 1}), "sessions")
        require(session.get("provider") == "codex" and session.get("message_count") == 2
                and session.get("tool_activity_count") == 1 and session.get("session_id")
                and hit.get("session_id") == session["session_id"], "Missing fixture session evidence")
        first = probe.tool("context.get_messages", {"session_id": session["session_id"], "limit": 1})
        message = single_record(first, "entries")
        require(message.get("entry_kind") == "message" and message.get("role") == "user"
                and message.get("content") == "stdio checkpoint ready API_KEY=" + REDACTED_SENTINEL,
                "Missing redacted fixture message evidence")
        require(isinstance(first.get("next_cursor"), str) and first["next_cursor"],
                "Missing message pagination cursor")
        second = probe.tool("context.get_messages",
            {"session_id": session["session_id"], "limit": 1, "cursor": first["next_cursor"]})
        response = single_record(second, "entries")
        require(response.get("entry_kind") == "message" and response.get("role") == "assistant"
                and response.get("content") == "fixture ready" and
                isinstance(second.get("next_cursor"), str) and second["next_cursor"],
                "Missing fixture assistant message evidence")
        third = probe.tool("context.get_messages",
            {"session_id": session["session_id"], "limit": 1, "cursor": second["next_cursor"]})
        activity = single_record(third, "entries")
        require(activity.get("entry_kind") == "tool_activity" and activity.get("tool_name") == "read"
                and activity.get("invocation") == "inspect stdio-latest-note.md"
                and activity.get("failed") is False and third.get("next_cursor") is None,
                "Missing terminal fixture tool activity evidence")
        resume = probe.tool("context.resume")
        decisions = resume.get("recent_decisions", {}).get("entries")
        require(isinstance(decisions, list) and decisions and isinstance(decisions[0], dict)
                and decisions[0].get("knowledge_entry_id"), "Missing resume decision evidence")
        decision = decisions[0]
        detail = probe.tool("context.get_knowledge",
                            {"knowledge_entry_id": decision["knowledge_entry_id"]})
        require(detail.get("knowledge_entry_id") == decision["knowledge_entry_id"]
                and detail.get("summary") == "d" * 600
                and detail.get("summary_is_truncated", False) is False,
                "Missing untruncated knowledge detail")
        require(detail.get("source_content_hash") ==
                "c7c1b0af653d904909a3a8bf08d226bb30f89294d37037790d8a6b3bdacbfa02"
                and message.get("message_id") and response.get("message_id")
                and detail.get("supporting_message_ids") ==
                [response["message_id"], message["message_id"]],
                "Missing ordered knowledge source evidence")
        knowledge = probe.tool("context.list_knowledge",
                               {"kind": "decision", "origin": "marked", "limit": 1})
        compact = single_record(knowledge, "entries")
        require(compact.get("knowledge_entry_id") == decision["knowledge_entry_id"]
                and compact.get("kind") == "decision" and compact.get("origin") == "marked"
                and isinstance(compact.get("summary"), str)
                and 0 < len(compact["summary"].encode("utf-8")) <= 512
                and compact.get("summary_is_truncated") is True
                and compact["summary"] == decision.get("summary")
                and "source_content_hash" not in compact and "supporting_message_ids" not in compact,
                "Missing compact bounded knowledge list evidence")
        require(isinstance(knowledge.get("next_cursor"), str) and knowledge["next_cursor"],
                "Missing knowledge pagination cursor")
        probe.tool("context.list_sessions", {"cursor": "not-a-valid-cursor", "limit": 1},
                   error_code="invalid_cursor")
        probe.finish()
    finally:
        probe.close()


def self_tests():
    test_path = os.path.join(os.path.dirname(__file__), "tests", "test_verify_mcp_stdio.py")
    return subprocess.call([sys.executable, test_path]) == 0

if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(0 if self_tests() else 1)
    if len(sys.argv) != 4:
        sys.exit("Usage: verify-mcp-stdio.py HELPER WORKSPACE SUPPORT_DIRECTORY | --self-test")
    try:
        verify_protocol([sys.argv[1], "--workspace", sys.argv[2]], sys.argv[2], sys.argv[3])
    except (ProbeFailure, OSError, ValueError, TypeError, KeyError) as failure:
        diagnostic = str(failure) if isinstance(failure, ProbeFailure) else "Helper probe could not complete"
        sys.exit("MCP stdio verification failed: " + diagnostic)
    print("MCP stdio verification passed")
