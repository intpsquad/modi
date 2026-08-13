"""LangGraph Studio 그래프 — **크레딧 0 · 네트워크 0**

Studio 는 운영과 **다른 그래프 객체**를 본다(`prepare` 노드가 앞에 하나 더 있다). 그래서
생기는 위험이 하나뿐인데 그게 치명적이다 — **그림과 실제 파이프라인이 조용히 갈리는 것.**
Studio 에서 보고 "여긴 이렇게 돌아가는군" 한 다음 운영이 다르게 돌면 디버깅이 거짓말이 된다.

`langgraph.json` 이 가리키는 경로가 실제로 존재하는지도 여기서 본다 — 그게 틀리면
`langgraph dev` 가 뜰 때야 알게 되고, 그때는 Studio 를 보려던 사람이 막힌다.
"""

import json
from pathlib import Path

from modi_ai.studio import graph as studio_graph
from modi_ai.suggest import SUGGEST_GRAPH

AI_ROOT = Path(__file__).resolve().parents[1]


def _edges(compiled) -> set[tuple[str, str]]:
    return {(e.source, e.target) for e in compiled.get_graph().edges}


class TestItMatchesProduction:
    def test_the_only_extra_node_is_prepare(self):
        studio = set(studio_graph.get_graph().nodes)
        production = set(SUGGEST_GRAPH.get_graph().nodes)

        assert studio - production == {"prepare"}
        assert production - studio == set(), "Studio 에 없는 운영 노드가 있다"

    def test_the_only_difference_in_edges_is_the_entry(self):
        """`prepare` 가 낀 진입부를 빼면 **엣지가 완전히 같아야 한다.**

        조건부 엣지까지 포함한다 — `critique → generate` 되돌아가는 엣지가 Studio 에서
        안 보이면 이 파일을 만든 이유가 없어진다.
        """
        entry_only = {("__start__", "prepare"), ("prepare", "select"), ("__start__", "select")}

        assert _edges(studio_graph) - entry_only == _edges(SUGGEST_GRAPH) - entry_only

    def test_the_regeneration_loop_is_visible(self):
        """Studio 로 보려는 것이 바로 이 엣지다."""
        assert ("critique", "generate") in _edges(studio_graph)

    def test_production_has_no_prepare_node(self):
        """운영 그래프에 Studio 전용 노드가 새면 안 된다 — 의존성을 두 번 만들게 된다."""
        assert "prepare" not in set(SUGGEST_GRAPH.get_graph().nodes)


class TestTheConfigPointsAtSomethingReal:
    def test_langgraph_json_targets_an_existing_object(self):
        config = json.loads((AI_ROOT / "langgraph.json").read_text(encoding="utf-8"))
        target = config["graphs"]["todo-suggestions"]
        module_path, attribute = target.split(":")

        assert (AI_ROOT / module_path).exists(), f"{module_path} 가 없다"
        assert attribute == "graph"

    def test_studio_is_a_separate_dependency_group(self):
        """`dev` 에 넣으면 CI 가 패키지 34개를 더 받는다 — Studio 는 사람이 볼 때만 필요하다."""
        pyproject = (AI_ROOT / "pyproject.toml").read_text(encoding="utf-8")

        assert "langgraph-cli" in pyproject.split("studio = [")[1].split("]")[0]
