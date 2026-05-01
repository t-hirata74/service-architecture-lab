"""ADR 0002: BOOLEAN MODE operator escape の不変条件 (regression: 文字列メンバシップ誤実装の修正)."""
from __future__ import annotations

import pytest

from services.retriever import to_boolean_query


class TestStripsBooleanOperators:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("foo", "foo"),
            ('"phrase"', "phrase"),
            ("foo -bar", "foo bar"),  # `-` は exclude operator → 落とす
            ("+required", "required"),
            ("(group)", "group"),
            ("foo* trail", "foo trail"),  # `*` は wildcard → 落とす
            ("~lower", "lower"),
            ("a < b > c", "  "),  # 1 文字 token は ngram 最小長未満で落ちる -> 全部空
            ("a@b", ""),  # `a@b` → "a b" → 1 文字なので両方落ちる
            ("単独引用'bar", "単独引用 bar"),
        ],
    )
    def test_operator_chars_become_space(self, raw, expected):
        result = to_boolean_query(raw)
        # 比較は connected token のみで判定 (空白の数は問わない)
        assert result.split() == expected.split()

    def test_minus_is_completely_stripped(self):
        # exclude operator の混入を確実に防ぐ regression test
        result = to_boolean_query("東京 -タワー")
        assert "-" not in result
        assert "東京" in result
        assert "タワー" in result

    def test_plus_is_completely_stripped(self):
        result = to_boolean_query("+東京 +タワー")
        assert "+" not in result

    def test_quote_is_completely_stripped(self):
        result = to_boolean_query('"完全一致"')
        assert '"' not in result
        assert "完全一致" in result

    def test_empty_query(self):
        assert to_boolean_query("") == ""

    def test_only_operators(self):
        assert to_boolean_query('+-"()~*<>@\\') == ""

    def test_japanese_passes_through(self):
        assert to_boolean_query("東京タワー") == "東京タワー"

    def test_alphanumeric_passes_through(self):
        # 1 文字 token は ngram_min_token_size=2 で落ちる
        assert to_boolean_query("AI 2024 RAG") == "AI 2024 RAG"

    def test_min_token_size_drops_single_chars(self):
        # ngram parser は n=2 が最小なので 1 文字を捨てる
        assert to_boolean_query("a bb ccc") == "bb ccc"

    def test_collapses_whitespace(self):
        assert to_boolean_query("foo    bar\t\nbaz") == "foo bar baz"
