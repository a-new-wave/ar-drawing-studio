# AR Drawing Studio 🎨📱

A premium AR tracing and drawing application for iOS and Android, inspired by the **iOS 26 "Liquid Glass"** aesthetic and **Snapchat's** camera-centric UI.

## ✨ Key Features

- **Snap-to-Surface Tracking**: High-precision AR placement that "sticks" perfectly to horizontal surfaces (floors, tables).
- **Gaze-Following Preview**: Real-time ghost preview that follows your phone's gaze before placement.
- **Smart Orientation**: Automatically lays images flat on horizontal surfaces.
- **Precision Controls**:
  - **Pinch-to-Scale**: Resize images from 5cm to 150cm.
  - **Two-Finger Rotation**: Twist to rotate images with degree-level precision.
  - **Live Metadata**: Real-time readout of current size and rotation.
  - **Vertical Opacity Slider**: Fine-tune transparency for perfect tracing.
- **Stable Anchoring**: Once placed, images are permanently locked to the real world, resisting AR drift.
- **Liquid Glass UI**: Stunning, translucent interface with glassmorphism effects and modern typography.
- **Mandatory Onboarding**: Seamless first-launch experience with built-in core feature tutorials.

## 🚀 Tech Stack

- **Framework**: Flutter
- **AR Engine**: ARKit (iOS) / ARCore (Android)
- **Styling**: Vanilla CSS concepts in Flutter, Glassmorphism
- **State Management**: Reactive State with Animate library integration

## 📂 Project Structure

- `lib/screens/workspace_screen.dart`: Core AR logic and UI.
- `lib/components/ar_view_wrapper.dart`: Platform-specific AR abstractions.
- `lib/theme/app_colors.dart`: iOS 26 "Neon" design tokens.

## 🛠️ Installation & Setup

1. **Clone the repo**:
   ```bash
   git clone https://github.com/a-new-wave/ar-drawing-studio.git
   ```
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Run on a physical device**:
   ```bash
   flutter run
   ```
   *Note: AR features require a physical iOS or Android device with AR capabilities.*

---
Created with ❤️ by **a-new-wave**
