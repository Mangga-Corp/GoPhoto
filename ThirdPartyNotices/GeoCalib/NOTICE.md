# GeoCalib — third-party notice

This app uses GeoCalib to estimate camera pitch, roll and focal length from a photo.

**GeoCalib: Single-image Calibration with Geometric Optimization** (ECCV 2024)
Alexander Veicht, Paul-Edouard Sarlin, Philipp Lindenberger, Marc Pollefeys
Source: https://github.com/cvg/GeoCalib (commit 1dedb29)
Copyright 2024 ETH Zurich

## Model weights (`geocalib-pinhole`, release v1.0)
Licensed under the Creative Commons Attribution 4.0 International License (CC BY 4.0),
https://creativecommons.org/licenses/by/4.0/ — full text in `LICENSE-WEIGHTS`.
The weights are provided "as-is", without warranties (CC BY 4.0, Section 5).

Changes made (Adapted Material):
- Converted from PyTorch to Core ML (`GeoCalibNet_fp32.mlpackage`, `GeoCalibNet_fp16.mlpackage`; fp16 = half precision).
- Only the network is converted; the optimizer runs separately in Swift.
- The NMF decoder's random initial bases are replaced by a fixed tensor (seed 0) so results are deterministic.
- The decoder's size-based resize is replaced by the equivalent scale-factor resize (identical output).

## Code
Licensed under the Apache License, Version 2.0 — full text in `LICENSE`.
Swift files derived from GeoCalib's Python code carry a header stating so:
`GeoCalibOptimizer.swift` (LM optimizer, pinhole) and `GeoCalibPreprocessor.swift` (image preprocessing).
Changes: ported from Python/PyTorch to Swift, pinhole camera and single image only.

This app is not affiliated with, sponsored or endorsed by ETH Zurich or the GeoCalib authors.
