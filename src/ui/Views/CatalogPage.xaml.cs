using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using EchoVisualizer.Services;
using EchoVisualizer.ViewModels;

namespace EchoVisualizer.Views
{
    public partial class CatalogPage : Page
    {
        private readonly CatalogViewModel _viewModel = AppVisualizerState.CatalogViewModel;

        public CatalogPage()
        {
            InitializeComponent();
            DataContext = _viewModel;
            CatalogGrid.ItemsSource = _viewModel.Items;
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
        }

        private void SearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
        {
            _viewModel.SearchText = sender.Text;
        }

        private void FavoritesFilterButton_Click(object sender, RoutedEventArgs e)
        {
            _viewModel.OnlyFavorites = !_viewModel.OnlyFavorites;
        }

        private void PresetCard_Tapped(object sender, TappedRoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.DataContext is CatalogItemModel item)
            {
                foreach (var it in _viewModel.Items)
                {
                    it.IsSelected = (it.Id == item.Id);
                }
            }
        }
    }
}
