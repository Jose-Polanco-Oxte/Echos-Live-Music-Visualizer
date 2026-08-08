using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;

namespace EchoVisualizer.ViewModels
{
    public sealed partial class CatalogItemModel : ObservableObject
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;

        [ObservableProperty]
        private bool isFavorite;

        [ObservableProperty]
        private bool isSelected;
    }

    public sealed partial class CatalogViewModel : ObservableObject
    {
        [ObservableProperty]
        private string searchText = string.Empty;

        [ObservableProperty]
        private bool onlyFavorites;

        public ObservableCollection<CatalogItemModel> Items { get; } = new()
        {
            new CatalogItemModel
            {
                Id = "bars",
                Name = "Ecualizador de Barras Espectral",
                Description = "Ecualizador de barras espectrales dinámico de alta resolución",
                IsFavorite = true,
                IsSelected = true
            }
        };
    }
}
