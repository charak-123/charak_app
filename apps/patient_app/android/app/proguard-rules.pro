# Flutter wrapper
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Agora RTC — loads native classes reflectively.
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Razorpay checkout, plus the annotation types it reflects over.
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keepclassmembers class * { @com.razorpay.* <methods>; }

# Firebase messaging.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
