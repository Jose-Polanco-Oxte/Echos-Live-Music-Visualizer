using System;
using Microsoft.UI.Dispatching;

namespace EchoVisualizer.Services
{
    public enum OverlayState
    {
        Full,
        ManualCollapsed,
        IdleHidden
    }

    public sealed class OverlayVisibilityService
    {
        public event EventHandler<OverlayState>? StateChanged;

        public OverlayState CurrentState { get; private set; } = OverlayState.Full;
        public bool IsSuspended { get; private set; }
        private OverlayState _stateBeforeIdle = OverlayState.Full;
        private readonly DispatcherQueueTimer _idleTimer;

        public OverlayVisibilityService(DispatcherQueue dispatcherQueue)
        {
            _idleTimer = dispatcherQueue.CreateTimer();
            _idleTimer.Interval = TimeSpan.FromSeconds(4);
            _idleTimer.IsRepeating = false;
            _idleTimer.Tick += (_, _) => EnterIdleHidden();
            _idleTimer.Start();
        }

        public void SuspendTimer()
        {
            IsSuspended = true;
            _idleTimer.Stop();
            if (CurrentState == OverlayState.IdleHidden)
            {
                SetState(OverlayState.Full);
            }
        }

        public void ResumeTimer()
        {
            IsSuspended = false;
            _idleTimer.Stop();
            _idleTimer.Start();
        }

        public void NotifyActivity()
        {
            if (IsSuspended)
            {
                return;
            }

            if (CurrentState == OverlayState.IdleHidden)
            {
                SetState(_stateBeforeIdle);
            }

            _idleTimer.Stop();
            _idleTimer.Start();
        }

        public void ToggleEyeButton()
        {
            if (IsSuspended || CurrentState == OverlayState.IdleHidden)
            {
                return;
            }

            SetState(CurrentState == OverlayState.Full
                ? OverlayState.ManualCollapsed
                : OverlayState.Full);
        }

        private void EnterIdleHidden()
        {
            if (IsSuspended || CurrentState == OverlayState.IdleHidden)
            {
                return;
            }

            _stateBeforeIdle = CurrentState;
            SetState(OverlayState.IdleHidden);
        }

        private void SetState(OverlayState state)
        {
            CurrentState = state;
            StateChanged?.Invoke(this, state);
        }
    }
}
