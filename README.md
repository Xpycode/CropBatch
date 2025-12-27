# CropBatch

A macOS app for batch cropping images with configurable edge trimming. Useful for removing bezels, status bars, or unwanted borders from multiple screenshots at once.

## Features

- Drag and drop or import multiple images
- Configure crop values for each edge (top, bottom, left, right)
- Visual crop editor with draggable handles
- Live preview of crop regions
- Batch export with progress tracking
- Save and load crop presets
- Smart UI detection for automatic crop suggestions
- Folder watching for automatic processing
- Batch review before export
- File size estimation

## Requirements

- macOS 15.0 or later
- Xcode 16+ (for building)

## Building

Open `CropBatch.xcodeproj` in Xcode and build with Cmd+B, or from the command line:

```bash
xcodebuild -project CropBatch.xcodeproj -scheme CropBatch -configuration Release
```

## Usage

1. Drop images onto the window or use File > Import
2. Adjust crop values using the sliders or drag handles in the preview
3. Optionally save settings as a preset for reuse
4. Click Export to save cropped images

## License

MIT
