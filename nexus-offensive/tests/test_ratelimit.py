"""Tests del rate limiter (token-bucket) con reloj falso y determinista."""

import pytest

from core.ratelimit import RateLimiter


class FakeClock:
    def __init__(self) -> None:
        self.t = 0.0

    def __call__(self) -> float:
        return self.t

    def advance(self, dt: float) -> None:
        self.t += dt


def make(default_rps, per_host=None, capacity=None):
    clk = FakeClock()
    rl = RateLimiter(
        default_rps,
        per_host=per_host,
        capacity=capacity,
        clock=clk,
        sleeper=lambda s: clk.advance(s),  # "dormir" = avanzar el reloj falso
    )
    return rl, clk


def test_burst_then_exhaust_then_refill():
    rl, clk = make(5, capacity=5)
    for _ in range(5):
        assert rl.try_acquire("h")      # agota el burst
    assert not rl.try_acquire("h")      # sin tokens
    clk.advance(0.2)                    # 0.2s * 5rps = 1 token
    assert rl.try_acquire("h")
    assert not rl.try_acquire("h")


def test_per_host_isolation():
    rl, _ = make(1, capacity=1)
    assert rl.try_acquire("a")
    assert not rl.try_acquire("a")      # bucket de "a" agotado
    assert rl.try_acquire("b")          # "b" tiene su propio bucket


def test_acquire_blocks_until_refill():
    rl, clk = make(10, capacity=1)
    assert rl.try_acquire("h")          # vacía el único token
    rl.acquire("h")                     # debe esperar ~0.1s (el sleeper avanza el reloj)
    assert clk.t >= 0.1 - 1e-9


def test_per_host_rate_override():
    rl, _ = make(10, per_host={"slow": 1})
    assert rl.try_acquire("slow")       # capacidad por host lento = max(1, 1) = 1
    assert not rl.try_acquire("slow")


def test_rejects_non_positive_rps():
    with pytest.raises(ValueError):
        RateLimiter(0)


def test_acquire_rejects_more_than_capacity():
    rl, _ = make(5, capacity=5)
    with pytest.raises(ValueError):
        rl.acquire("h", tokens=6)
