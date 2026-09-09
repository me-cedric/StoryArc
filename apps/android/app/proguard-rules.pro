# R8 keep rules are audited, not inherited. Every rule below states why it
# exists; a rule with no reason is a rule nobody can safely delete later.

# Compose and AndroidX ship their own consumer rules — nothing needed here yet.
# Serialization and reflection-based rules land with the connector layer.

# jcifs-ng logs through slf4j, and slf4j 1.x looks for a binding class that no
# dependency here provides — the library falls back to a no-op logger at run time.
# R8 sees the reference and refuses to finish, so the warning is suppressed rather
# than the class kept: keeping it is impossible, it does not exist.
-dontwarn org.slf4j.impl.StaticLoggerBinder
