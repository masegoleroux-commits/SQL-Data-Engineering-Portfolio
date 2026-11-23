# Data dictionary

| Item | Meaning |
|---|---|
| Frame | 25 per second in the source; every 5th kept (frame 5, 10, 15 ...) |
| x, y | 0-1 across the pitch; converted to metres (x × 105, y × 68) |
| NaN | player not on the pitch, or ball not visible |
| Event Start Frame | frame the event began; snapped to the nearest stored sample |
| From / To | passer and receiver codes (Player1 ...) |
