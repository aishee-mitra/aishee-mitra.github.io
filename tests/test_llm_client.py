"""
test_llm_client.py — Unit tests for llm_client model/provider resolution and fallback.
"""
from __future__ import annotations

import os
from unittest import TestCase, mock

import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
import llm_client


class TestGetModelAndProvider(TestCase):
    def test_get_model_and_provider_defaults(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            m, p = llm_client.get_model_and_provider("composer")
            self.assertIsNone(m)
            self.assertIsNone(p)

            m, p = llm_client.get_model_and_provider("worker")
            self.assertEqual(m, "nvidia/nemotron-3.5-lightning:free")
            self.assertEqual(p, "openrouter")

    def test_role_prefixed_env_takes_precedence(self):
        env = {
            "BLOG_COMPOSER_MODEL": "my/composer",
            "BLOG_COMPOSER_PROVIDER": "myprovider",
            "BLOG_MODEL": "old",
            "BLOG_PROVIDER": "oldprov",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            m, p = llm_client.get_model_and_provider("composer")
            self.assertEqual(m, "my/composer")
            self.assertEqual(p, "myprovider")

    def test_legacy_env_fallback_for_composer(self):
        env = {"BLOG_MODEL": "legacy/model", "BLOG_PROVIDER": "legacyprov"}
        with mock.patch.dict(os.environ, env, clear=True):
            m, p = llm_client.get_model_and_provider("composer")
            self.assertEqual(m, "legacy/model")
            self.assertEqual(p, "legacyprov")

    def test_empty_role_vars_omit_model(self):
        env = {"BLOG_COMPOSER_MODEL": "   ", "BLOG_COMPOSER_PROVIDER": "  "}
        with mock.patch.dict(os.environ, env, clear=True):
            m, p = llm_client.get_model_and_provider("composer")
            self.assertIsNone(m)
            self.assertIsNone(p)
