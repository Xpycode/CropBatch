# Corner Radius, Blur & Watermark

CropBatch can apply finishing effects to every image in the batch.

## Corner Radius

Round the corners of the output, with per-corner control. Because rounded corners need transparency, enabling this **auto-switches the export format to PNG**.

## Blur Regions

Blur sensitive areas — redact names, faces, keys, or anything you don't want to share. Each blur region has an adjustable **intensity**. Toggle the blur tool with the **B** key.

![A blur region drawn over the image, with the Blur tab's style and intensity controls in the settings panel.](effects.jpg)

## Watermarks

Overlay **text or an image** on every export. Options include:

- Position and opacity
- Color, shadow, and outline
- Variables (e.g. file name) in text watermarks

![The Watermark panel with text tokens such as {year} and {date}, and the watermark overlaid on the image.](effects-watermark.jpg)

Watermarks are applied to the final cropped image, so they sit correctly on the output you actually keep.
