# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/Cellar/android-sdk/24.3.3/tools/proguard/proguard-android.txt

# Keep SLF4J classes (used by some dependencies)
-dontwarn org.slf4j.**
-keep class org.slf4j.** { *; }

# Add any other project specific keep options here