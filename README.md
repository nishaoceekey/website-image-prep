# Website Image Prep

An open-source, offline macOS app for preparing product images for websites and online catalogues.

All image processing, spreadsheet parsing, and screenshot OCR happen locally on the Mac. The app does not upload images or naming data to a server.

## What it does

- Drops images or entire folders into a batch queue.
- Creates exact custom-sized canvases (800 × 800 px by default).
- Centres images without changing their proportions.
- Lets each image be dragged and zoomed independently.
- Exports white-background sRGB files as JPEG, PNG, flattened PSD, or any combination.
- Keeps JPEG files under a chosen MB limit; PNG and PSD preserve full-quality pixels.
- Tries 100% JPEG quality first and compresses only when the selected maximum size requires it.
- Offers Natural, Clear, and Extra Sharp clarity processing plus source-resolution warnings.
- Accepts PNG and PSD source images in addition to JPG, HEIC, TIFF, and other common formats.
- Renames files from CSV, Excel `.xlsx`, or screenshot text captured with offline OCR.
- Supports dragging a naming screenshot/file or pasting a screenshot from the clipboard.
- Shows a review table so OCR or spreadsheet names can be corrected before applying.
- Prevents accidental overwrites when two requested names are the same.

## CSV format

Recommended:

```csv
original_filename,new_filename
IMG_001.png,product-blue-front.jpg
IMG_002.png,product-blue-side.jpg
```

A single column of new names is also accepted and is matched to the image list in order.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer

## Build and run

```sh
swift build
swift run WebsiteImagePrep
```

The first build can take a little longer while Swift prepares the project. No third-party package dependencies are required.

## Self-test

Run the app with its self-test option:

```sh
swift run WebsiteImagePrep --self-test
```

The self-test exercises CSV and XLSX parsing, file naming, image sizing, and export behavior without uploading data.

## Privacy

Website Image Prep works entirely offline. Files are read only after the user selects or drops them into the app, and exports go to a user-selected folder. macOS may request access to the relevant files and folders.

## Contributing

Bug reports and focused improvements are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change.

## License

The original source code in this repository is available under the [MIT License](LICENSE). Apple frameworks and supported file formats remain subject to their respective terms.
