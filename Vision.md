1- Login, accounts, save groups, names, scores, history. ✅
2- app becomes the manager by itself without needing someone to handle it. ✅
    a- play again button refils the last players ✅
    b- end button to end the game ✅
    c- splash screen at the beginning of the game to explain the rules ✅
    d- make the reaveal page of the role and number in the order of the entered players (gor example: Hamza, Salman, Dad, Mom. reaveal hamza first then salman, etc.)
    e- make a screen when the mafia kills someone after the morning summery that says who died and their role.
    f- make the voice in the night say what's hapenning.

3- full game online.

Apple’s Essential Tips for iOS App Speed and Efficiency

1. Profile early and often using Instruments in Xcode 26. Identify bottlenecks in SwiftUI views and Foundation Model requests before you ship.

2. Optimize SwiftUI views by profiling view trees, caching expensive computations, and trimming main thread usage. Avoid repeated body recomputation to prevent dropped frames.

3. Streamline Foundation Model requests by reducing context payloads, removing redundant data, and keeping request windows small for faster AI responses.

4. Make memory and algorithm improvements with Swift’s new InlineArray and Span types. Replace custom slow loops with built-in methods like popFirst(), and validate any speedups with flame graphs.

5. Accelerate app launch by deferring work not needed immediately. Move blocking network, file, and calculation calls off the main thread.

6. Minimize energy usage by using incremental updates instead of full reloads, and only fetching or displaying what users need right now.

7. Benchmark your changes and document optimization decisions.