import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location(
    "verify_mcp_stdio", Path(__file__).resolve().parents[1] / "verify-mcp-stdio.py")
probe_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe_module)
ProbeFailure = probe_module.ProbeFailure
verify_protocol = probe_module.verify_protocol


class ProbeTests(unittest.TestCase):
    def fixture_responses(self):
        tool_names = ["current_project", "resume", "search", "list_artifacts", "get_artifact",
                      "list_sessions", "get_session", "get_messages", "list_knowledge", "get_knowledge"]
        content = [
            {"name": "anchor-stdio-fixture", "project_id": "project", "workspace_path": "/fixture/workspace"},
            {"hits": [{"session_id": "session", "provider": "codex", "excerpt": "stdio checkpoint ready"}]},
            {"artifacts": [{"artifact_id": "artifact", "name": "stdio-latest-note.md"}]},
            {"code": "context_unavailable"},
            {"sessions": [{"session_id": "session", "provider": "codex", "message_count": 2, "tool_activity_count": 1}]},
            {"entries": [{"entry_kind": "message", "message_id": "message", "role": "user", "content": "stdio checkpoint ready API_KEY=[redacted:assigned-secret]"}], "next_cursor": "next-page"},
            {"entries": [{"entry_kind": "message", "message_id": "response", "role": "assistant", "content": "fixture ready"}], "next_cursor": "next-page-2"},
            {"entries": [{"entry_kind": "tool_activity", "tool_name": "read", "invocation": "inspect stdio-latest-note.md", "failed": False}]},
            {"recent_decisions": {"entries": [self.compact_decision()], "has_more": True}},
            {**self.compact_decision(), "summary": "d" * 600, "summary_is_truncated": False,
             "source_content_hash": "c7c1b0af653d904909a3a8bf08d226bb30f89294d37037790d8a6b3bdacbfa02",
             "supporting_message_ids": ["response", "message"]},
            {"entries": [self.compact_decision()], "next_cursor": "next-knowledge"},
            {"code": "invalid_cursor"},
        ]
        return [{"protocolVersion": "2025-11-25", "serverInfo": {"name": "anchor"}}, {
                "tools": [{"name": "context." + name} for name in tool_names]}] + [
                    {"isError": index in (3, 11), "structuredContent": fields}
                    for index, fields in enumerate(content)]

    def compact_decision(self):
        return {"knowledge_entry_id": "decision", "kind": "decision", "origin": "marked",
                "summary": "d" * 497 + "… [truncated]", "summary_is_truncated": True}

    def probe(self, responses=None, stdout_suffix="", stderr="", exit_code=0, hang=False):
        responses = self.fixture_responses() if responses is None else responses
        program = """
import json, os, sys, time
responses = json.loads(sys.argv[1])
assert os.environ['ANCHOR_MCP_TEST_SUPPORT_DIRECTORY'] == '/fixture'
initialized = False
for line in sys.stdin:
    request = json.loads(line)
    assert request['jsonrpc'] == '2.0'
    if request['method'] == 'notifications/initialized':
        initialized = True
        continue
    if request['method'] != 'initialize':
        assert initialized
    else:
        assert request['params']['protocolVersion'] == '2025-11-25'
    if request['method'] == 'tools/call':
        names = ['current_project', 'search', 'list_artifacts', 'get_artifact', 'list_sessions',
                 'get_messages', 'get_messages', 'get_messages', 'resume', 'get_knowledge',
                 'list_knowledge', 'list_sessions']
        assert request['params']['name'] == 'context.' + names[request['id'] - 3]
        arguments = request['params']['arguments']
        if request['id'] in (4, 5, 7, 8, 9, 10, 13, 14): assert arguments['limit'] == 1
        if request['id'] == 9: assert arguments['cursor'] == 'next-page'
        if request['id'] == 10: assert arguments['cursor'] == 'next-page-2'
        if request['id'] == 11: assert arguments == {}
        if request['id'] == 12: assert arguments == {'knowledge_entry_id': 'decision'}
        if request['id'] == 13: assert arguments == {'kind': 'decision', 'origin': 'marked', 'limit': 1}
        if request['id'] == 14: assert arguments['cursor'] == 'not-a-valid-cursor'
    print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': responses.pop(0)}), flush=True)
sys.stdout.write(sys.argv[2])
sys.stderr.write(sys.argv[3])
sys.stdout.flush()
sys.stderr.flush()
if sys.argv[5] == 'True': time.sleep(10)
sys.exit(int(sys.argv[4]))
"""
        return verify_protocol(
            [sys.executable, "-u", "-c", program, json.dumps(responses), stdout_suffix,
             stderr, str(exit_code), str(hang)], "/fixture/workspace", "/fixture", timeout=1)

    def test_accepts_complete_paginated_exchange(self):
        self.probe()

    def test_accepts_equivalent_workspace_spelling(self):
        responses = self.fixture_responses()
        responses[2]["structuredContent"]["workspace_path"] = "/fixture/./workspace"
        self.probe(responses)

    def test_rejects_broken_protocol_evidence(self):
        for response_index, key, replacement in [
            (0, "protocolVersion", "old"), (1, "tools", []),
            (2, "structuredContent", {}), (3, "structuredContent", {"hits": []}),
            (5, "isError", False), (6, "structuredContent", {"sessions": []}),
            (7, "structuredContent", {"entries": []}),
            (7, "structuredContent", {"entries": [{}, {}]}),
            (8, "structuredContent", {"entries": [{"entry_kind": "message"}]}),
            (9, "structuredContent", {"code": "read_failed"}),
        ]:
            with self.subTest(response=response_index, key=key):
                responses = copy.deepcopy(self.fixture_responses())
                responses[response_index][key] = replacement
                with self.assertRaises(ProbeFailure):
                    self.probe(responses)

    def test_rejects_missing_or_unbounded_knowledge_evidence(self):
        for response_index, key, replacement in [
            (10, "recent_decisions", {"entries": []}),
            (11, "knowledge_entry_id", "unrelated"),
            (11, "summary", "d" * 512), (11, "summary_is_truncated", True),
            (11, "source_content_hash", ""), (11, "supporting_message_ids", []),
            (11, "supporting_message_ids", ["message", "response"]),
            (12, "entries", []), (12, "next_cursor", None),
            (12, "entries", [{**self.compact_decision(), "summary": "d" * 600}]),
            (12, "entries", [{**self.compact_decision(), "summary_is_truncated": False}]),
            (12, "entries", [{**self.compact_decision(), "knowledge_entry_id": "other"}]),
        ]:
            with self.subTest(response=response_index, key=key):
                responses = self.fixture_responses()
                responses[response_index]["structuredContent"][key] = replacement
                with self.assertRaises(ProbeFailure):
                    self.probe(responses)

    def test_rejects_stdout_noise_and_unterminated_json(self):
        for suffix in ("diagnostic\n", "[]\n", "{}", "{}\n", "\n"):
            with self.subTest(suffix=suffix), self.assertRaises(ProbeFailure):
                self.probe(stdout_suffix=suffix)

    def test_rejects_stderr_leaks_nonzero_exit_and_eof_hang(self):
        for arguments in ({"stderr": "[redacted:assigned-secret]"},
                          {"stderr": "anchor-stdio-raw-secret-0123456789"},
                          {"exit_code": 3}, {"hang": True}):
            with self.subTest(arguments=arguments), self.assertRaises(ProbeFailure):
                self.probe(**arguments)


if __name__ == "__main__":
    unittest.main(verbosity=2)
