using Microsoft.UI.Windowing;

namespace EchoVisualizer.Services
{
    public sealed class FullScreenService
    {
        private AppWindow? _appWindow;

        public bool IsFullScreen => _appWindow?.Presenter is OverlappedPresenter presenter &&
                                     presenter.State == OverlappedPresenterState.Maximized;

        public void Initialize(AppWindow appWindow)
        {
            _appWindow = appWindow;
        }

        public void Toggle()
        {
            if (_appWindow is null)
            {
                return;
            }

            if (_appWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen)
            {
                _appWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            }
            else
            {
                _appWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
            }
        }
    }
}
