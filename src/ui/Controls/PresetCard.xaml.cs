using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace EchoVisualizer.Controls
{
    public enum PresetCardSize
    {
        Small,
        Large
    }

    public partial class PresetCard : UserControl
    {
        public static readonly DependencyProperty PresetTitleProperty =
            DependencyProperty.Register(nameof(PresetTitle), typeof(string), typeof(PresetCard),
                new PropertyMetadata(string.Empty, (d, e) => ((PresetCard)d).TitleText.Text = (string)e.NewValue));

        public static readonly DependencyProperty IsSelectedPresetProperty =
            DependencyProperty.Register(nameof(IsSelectedPreset), typeof(bool), typeof(PresetCard),
                new PropertyMetadata(false, (d, e) => ((PresetCard)d).UpdateSelectedState((bool)e.NewValue)));

        public static readonly DependencyProperty IsFavoritePresetProperty =
            DependencyProperty.Register(nameof(IsFavoritePreset), typeof(bool), typeof(PresetCard),
                new PropertyMetadata(false, (d, e) => ((PresetCard)d).UpdateFavoriteState((bool)e.NewValue)));

        public static readonly DependencyProperty CardSizeProperty =
            DependencyProperty.Register(nameof(CardSize), typeof(PresetCardSize), typeof(PresetCard),
                new PropertyMetadata(PresetCardSize.Small, (d, e) => ((PresetCard)d).UpdateCardSize((PresetCardSize)e.NewValue)));

        public string PresetTitle
        {
            get => (string)GetValue(PresetTitleProperty);
            set => SetValue(PresetTitleProperty, value);
        }

        public bool IsSelectedPreset
        {
            get => (bool)GetValue(IsSelectedPresetProperty);
            set => SetValue(IsSelectedPresetProperty, value);
        }

        public bool IsFavoritePreset
        {
            get => (bool)GetValue(IsFavoritePresetProperty);
            set => SetValue(IsFavoritePresetProperty, value);
        }

        public PresetCardSize CardSize
        {
            get => (PresetCardSize)GetValue(CardSizeProperty);
            set => SetValue(CardSizeProperty, value);
        }

        public event RoutedEventHandler? FavoriteToggled;

        public PresetCard()
        {
            InitializeComponent();
        }

        private void UpdateSelectedState(bool isSelected)
        {
            SelectedBorder.Visibility = isSelected ? Visibility.Visible : Visibility.Collapsed;
        }

        private void UpdateFavoriteState(bool isFavorite)
        {
            FavoriteButton.IsChecked = isFavorite;
            StarIcon.Glyph = isFavorite ? "\uE735" : "\uE734"; // Filled vs Outline star
            StarIcon.Foreground = isFavorite
                ? (Brush)Application.Current.Resources["BrushAccent"]
                : (Brush)Application.Current.Resources["BrushTextSecondary"];
        }

        private void UpdateCardSize(PresetCardSize size)
        {
            if (size == PresetCardSize.Large)
            {
                ContainerGrid.Width = 184;
                ContainerGrid.Height = 120;
            }
            else
            {
                ContainerGrid.Width = 152;
                ContainerGrid.Height = 96;
            }
        }

        private void FavoriteButton_Click(object sender, RoutedEventArgs e)
        {
            IsFavoritePreset = FavoriteButton.IsChecked == true;
            FavoriteToggled?.Invoke(this, e);
        }
    }
}
