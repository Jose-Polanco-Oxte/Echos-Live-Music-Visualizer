using System;
using System.Threading.Tasks;
using Xunit;

namespace EchoVisualizer.Tests
{
    public enum SimulationOverlayState
    {
        Full,
        ManualCollapsed,
        IdleHidden
    }

    public sealed class TestableOverlayController
    {
        public SimulationOverlayState CurrentState { get; private set; } = SimulationOverlayState.Full;
        public bool IsCursorHidden { get; private set; }
        public bool IsFullScreen { get; set; } = true;
        public int IdleIntervalMs { get; set; } = 100; // Accelerated for fast xUnit execution

        private DateTime _lastActivity = DateTime.UtcNow;

        public void NotifyActivity()
        {
            _lastActivity = DateTime.UtcNow;
            if (CurrentState == SimulationOverlayState.IdleHidden)
            {
                SetState(SimulationOverlayState.Full);
            }
        }

        public void SimulateTick()
        {
            if (CurrentState == SimulationOverlayState.IdleHidden) return;

            var elapsed = (DateTime.UtcNow - _lastActivity).TotalMilliseconds;
            if (elapsed >= IdleIntervalMs)
            {
                SetState(SimulationOverlayState.IdleHidden);
            }
        }

        private void SetState(SimulationOverlayState state)
        {
            CurrentState = state;
            UpdateCursorVisibility();
        }

        public void UpdateCursorVisibility()
        {
            if (IsFullScreen && CurrentState == SimulationOverlayState.IdleHidden)
            {
                IsCursorHidden = true;
            }
            else
            {
                IsCursorHidden = false;
            }
        }
    }

    public sealed class CursorAutoHideTests
    {
        [Fact]
        public void CursorStateContract_InitialState_IsCursorVisible()
        {
            var controller = new TestableOverlayController();
            Assert.Equal(SimulationOverlayState.Full, controller.CurrentState);
            Assert.False(controller.IsCursorHidden);
        }

        [Fact]
        public async Task CursorStateContract_Wait5Seconds_CursorHides_PointerMoves_CursorShows_Wait5Seconds_CursorHidesAgain()
        {
            var controller = new TestableOverlayController
            {
                IsFullScreen = true,
                IdleIntervalMs = 150 // Accelerated 150ms equivalent to 5s in production
            };

            // Initial state
            Assert.False(controller.IsCursorHidden);

            // 1. Wait for idle duration
            await Task.Delay(200);
            controller.SimulateTick();

            Assert.Equal(SimulationOverlayState.IdleHidden, controller.CurrentState);
            Assert.True(controller.IsCursorHidden); // Verified: Cursor is hidden after 5s idle

            // 2. Mouse moves (PointerMoved)
            controller.NotifyActivity();

            Assert.Equal(SimulationOverlayState.Full, controller.CurrentState);
            Assert.False(controller.IsCursorHidden); // Verified: Cursor re-appears upon pointer movement

            // 3. Wait for idle duration again
            await Task.Delay(200);
            controller.SimulateTick();

            Assert.Equal(SimulationOverlayState.IdleHidden, controller.CurrentState);
            Assert.True(controller.IsCursorHidden); // Verified: Cursor hides AGAIN on second 5s idle cycle

            // 4. Mouse moves second time
            controller.NotifyActivity();

            Assert.Equal(SimulationOverlayState.Full, controller.CurrentState);
            Assert.False(controller.IsCursorHidden); // Verified: Cursor shows AGAIN on second pointer movement
        }

        [Fact]
        public async Task CursorStateContract_MultipleRepeated5SecondCycles_MaintainsConsistency()
        {
            var controller = new TestableOverlayController
            {
                IsFullScreen = true,
                IdleIntervalMs = 50
            };

            for (int cycle = 1; cycle <= 10; cycle++)
            {
                // Idle wait
                await Task.Delay(75);
                controller.SimulateTick();
                Assert.True(controller.IsCursorHidden, $"Cycle {cycle}: Cursor must hide when idle in fullscreen");

                // User activity (mouse move)
                controller.NotifyActivity();
                Assert.False(controller.IsCursorHidden, $"Cycle {cycle}: Cursor must restore when pointer moves");
            }
        }
    }
}
