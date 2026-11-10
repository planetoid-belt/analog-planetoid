## list of states
- (A) Attract:  Exhibit is waiting for new users. A blank planetoid is displayed.
  - -> P: Users have chosen their instruments and are ready to begin. Hosts start the experience.
  - -> G: Hosts decide to show the galaxy map.
- (P) Prepare:  A count-in, at least. Perhaps some tutorial or more fancy build-up.
  - -> C: After some time creation begins automatically.
  - -> A: The experiecnce can be canceled by the hosts.
- (C) Create:   Users are creating a planetoid. Alternates between playing and listening.
  - -> F: When planetoid creation has completed it will be displayed. (Planetoid is saved?)
  - -> A: The experiecnce can be canceled by the hosts.
- (F) Finished: A completed planetoid is on display. The song of the planetoid is playing.
  - -> A: The experience is reset by the hosts for new users to take part.
  - -> G: Hosts decide to show the galaxy map.
- (G) Galaxy:   The galaxy map shows all created planetoids.
  - -> A: The experience is reset by the hosts for new users to take part.
  - -> A: A particular planet is chosen to be put on display.

## State diagram
 ----> G <-----
v              v
A -> P -> C -> F
^    |    |    |
 --------------