# Releases & Revision Matrix

All commits and manifests are strictly verified from official Google Android Open Source Project (AOSP) repositories.

---

## LLVM Releases Matrix

Every LLVM release produces prebuilt artifacts for both host platforms:
- **Platform Bionic (Android):** `custom-llvm-<rev>-<arch>-linux-android.tar.xz` (`aarch64`, `armv7a`, `x86_64`, `i686`)
- **Platform Linux (GNU):** `custom-llvm-<rev>-<arch>-linux-gnu.tar.xz` (`aarch64`, `armv7a`, `x86_64`, `i686`)

| LLVM Major | Clang Revision | Git Tag | AOSP llvm-project Commit | AOSP llvm_android Commit | AOSP Manifest | Artifact Pattern |
| :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **17** | `clang-r487747c` | `llvm-r487747c` | `d9f89f4d16663d5012e5c09495f3b30ece3d2362` | `8443a75fcd5c80245b194f6510b98a11098fe7fe` | `manifest_10087095.xml` | `custom-llvm-r487747c-<target>.tar.xz` |
| **17** | `clang-r487747d` | `llvm-r487747d` | `d9f89f4d16663d5012e5c09495f3b30ece3d2362` | `56a5097db0d7057c2d011dad8550cb3f3c7e9103` | `manifest_10552028.xml` | `custom-llvm-r487747d-<target>.tar.xz` |
| **17** | `clang-r487747e` | `llvm-r487747e` | `d9f89f4d16663d5012e5c09495f3b30ece3d2362` | `0f058ab00ec6c9b8b39956c1393bcc405a5498d3` | `manifest_11349228.xml` | `custom-llvm-r487747e-<target>.tar.xz` |
| **18** | `clang-r522817`  | `llvm-r522817`  | `d8003a456d14a3deb8054cdaa529ffbf02d9b262` | `5ab132bd1afa945695853fa093dfcc839e45f97c` | `manifest_12027248.xml` | `custom-llvm-r522817-<target>.tar.xz` |
| **18** | `clang-r522817b` | `llvm-r522817b` | `d8003a456d14a3deb8054cdaa529ffbf02d9b262` | `2a4ee244d6dd0dcb8365590b898f7a40ec3cb87a` | `manifest_12285214.xml` | `custom-llvm-r522817b-<target>.tar.xz` |
| **18** | `clang-r522817c` | `llvm-r522817c` | `d8003a456d14a3deb8054cdaa529ffbf02d9b262` | `31a1d3747b77b10185c0adf03ae6036b474719c7` | `manifest_12470979.xml` | `custom-llvm-r522817c-<target>.tar.xz` |
| **18** | `clang-r522817d` | `llvm-r522817d` | `d8003a456d14a3deb8054cdaa529ffbf02d9b262` | `3503453cd6ccac933b4a1ec5255b7fc29851ea6b` | `manifest_13691557.xml` | `custom-llvm-r522817d-<target>.tar.xz` |
| **19** | `clang-r530567b` | `llvm-r530567b` | `97a699bf4812a18fb657c2779f5296a4ab2694d2` | `8dfdf1fc93652ba216e3bcea41bbcd124f1185a5` | `manifest_12642944.xml` | `custom-llvm-r530567b-<target>.tar.xz` |
| **19** | `clang-r530567d` | `llvm-r530567d` | `97a699bf4812a18fb657c2779f5296a4ab2694d2` | `4de061b7b428ebac7a6f71abe1cf2d03ebb00ee5` | `manifest_13324770.xml` | `custom-llvm-r530567d-<target>.tar.xz` |
| **19** | `clang-r530567e` | `llvm-r530567e` | `97a699bf4812a18fb657c2779f5296a4ab2694d2` | `e727bfb014bd436f581a66a450c939a6983a1fc3` | `manifest_13624864.xml` | `custom-llvm-r530567e-<target>.tar.xz` |
| **21** | `clang-r563880c` | `llvm-r563880c` | `5e96669f06077099aa41290cdb4c5e6fa0f59349` | `1dab3288f660d43a6cb2479107e2b54b3ab0a2a1` | `manifest_13989888.xml` | `custom-llvm-r563880c-<target>.tar.xz` |
| **21** | `clang-r574158c` | `llvm-r574158c` | `9f872551d3c681d06fd303b36f16ed5c274735eb` | `9e20ac0b949feedcfe3da791189310f6ebcbc7a8` | `manifest_16134705.xml` | `custom-llvm-r574158c-<target>.tar.xz` |

---

## NDK Releases Matrix

Every NDK release produces prebuilt artifacts for both host platforms:
- **Platform Bionic (Android):** `custom-android-ndk-<release>-<arch>-linux-android.tar.xz` (`aarch64`, `armv7a`, `x86_64`, `i686`)
- **Platform Linux (GNU):** `custom-android-ndk-<release>-<arch>-linux-gnu.tar.xz` (`aarch64`, `armv7a`, `x86_64`, `i686`)

| NDK Release | Git Tag | Required LLVM Revision | LLVM Tag | Official AOSP Base Archive | NDK Release Artifact Pattern |
| :---: | :---: | :---: | :---: | :---: | :--- |
| `r26`  | `ndk-r26`  | `clang-r487747c` | `llvm-r487747c` | `android-ndk-r26-linux.zip`  | `custom-android-ndk-r26-<target>.tar.xz`  |
| `r26b` | `ndk-r26b` | `clang-r487747d` | `llvm-r487747d` | `android-ndk-r26b-linux.zip` | `custom-android-ndk-r26b-<target>.tar.xz` |
| `r26c` | `ndk-r26c` | `clang-r487747d` | `llvm-r487747d` | `android-ndk-r26c-linux.zip` | `custom-android-ndk-r26c-<target>.tar.xz` |
| `r26d` | `ndk-r26d` | `clang-r487747e` | `llvm-r487747e` | `android-ndk-r26d-linux.zip` | `custom-android-ndk-r26d-<target>.tar.xz` |
| `r27`  | `ndk-r27`  | `clang-r522817`  | `llvm-r522817`  | `android-ndk-r27-linux.zip`  | `custom-android-ndk-r27-<target>.tar.xz`  |
| `r27b` | `ndk-r27b` | `clang-r522817b` | `llvm-r522817b` | `android-ndk-r27b-linux.zip` | `custom-android-ndk-r27b-<target>.tar.xz` |
| `r27c` | `ndk-r27c` | `clang-r522817c` | `llvm-r522817c` | `android-ndk-r27c-linux.zip` | `custom-android-ndk-r27c-<target>.tar.xz` |
| `r27d` | `ndk-r27d` | `clang-r522817d` | `llvm-r522817d` | `android-ndk-r27d-linux.zip` | `custom-android-ndk-r27d-<target>.tar.xz` |
| `r28`  | `ndk-r28`  | `clang-r530567b` | `llvm-r530567b` | `android-ndk-r28-linux.zip`  | `custom-android-ndk-r28-<target>.tar.xz`  |
| `r28b` | `ndk-r28b` | `clang-r530567d` | `llvm-r530567d` | `android-ndk-r28b-linux.zip` | `custom-android-ndk-r28b-<target>.tar.xz` |
| `r28c` | `ndk-r28c` | `clang-r530567e` | `llvm-r530567e` | `android-ndk-r28c-linux.zip` | `custom-android-ndk-r28c-<target>.tar.xz` |
| `r29`  | `ndk-r29`  | `clang-r563880c` | `llvm-r563880c` | `android-ndk-r29-linux.zip`  | `custom-android-ndk-r29-<target>.tar.xz`  |
| `r30`  | `ndk-r30`  | `clang-r574158c` | `llvm-r574158c` | `android-ndk-r30-linux.zip`  | `custom-android-ndk-r30-<target>.tar.xz`  |
