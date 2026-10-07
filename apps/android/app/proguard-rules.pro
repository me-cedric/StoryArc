# R8 keep rules are audited, not inherited. Every rule below states why it
# exists; a rule with no reason is a rule nobody can safely delete later.

# Compose and AndroidX ship their own consumer rules — nothing needed here yet.
# Serialization and reflection-based rules land with the connector layer.

# smbj (ADR-0019) and the libraries it brings.
#
# MBassador finds an event handler by its @Handler annotation, at run time. smbj's
# SMBClient, Connection and Session each subscribe one, and a handler R8 renamed
# or stripped would leave a closed session in the client's tables. So the
# annotation is kept, with every method that carries it.
-keepattributes RuntimeVisibleAnnotations
-keepclassmembers class * {
    @net.engio.mbassy.listener.Handler <methods>;
}
-keep @interface net.engio.mbassy.listener.**
# MBassador's expression-language filters use javax.el, which Android does not
# have and no StoryArc subscription uses. The classes cannot be kept; they do
# not exist, so the warning is suppressed.
-dontwarn javax.el.**
# smbj's Kerberos path uses GSS-API, which Android does not have. smbj checks
# for android.os.Build and never registers that authenticator on Android.
-dontwarn org.ietf.jgss.**
