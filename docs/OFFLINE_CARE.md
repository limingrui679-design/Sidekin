# Offline care simulation

Sidekin uses the same care model in Swift and TypeScript. A sleeping pet gains 18 energy per hour and wakes when its energy reaches 99. Given a catch-up interval, the engine computes the time to that event, integrates sleeping rates up to it, clamps each statistic, and applies waking rates to the remaining interval. The catch-up interval is capped at twelve hours.

For a sleeping pet starting with energy 81, hunger 80, and mood 99.8, a four-hour absence contains one sleeping hour and three waking hours. Energy ends at 92.4, hunger at 66, and mood at 96.1. The mood calculation includes saturation at 100 before the pet wakes. Both engines compare this result with sixteen consecutive fifteen-minute updates in their lifecycle checks.
