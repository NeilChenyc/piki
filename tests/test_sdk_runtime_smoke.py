import os

import pytest

from agent_service.config import ServiceConfig, load_environment
from agent_service.runtime import PikiWikiAgentRunner


@pytest.mark.skipif(
    os.environ.get("PIKI_RUN_REAL_SDK_TEST") != "1",
    reason="real SDK smoke test is opt-in",
)
def test_real_sdk_smoke_when_enabled():
    load_environment()
    config = ServiceConfig(enable_sdk_runtime=True)
    runner = PikiWikiAgentRunner()

    result = runner.smoke_test(config=config)

    assert result.ok, result.error
    assert "Piki SDK smoke test ok." in (result.output or "")
