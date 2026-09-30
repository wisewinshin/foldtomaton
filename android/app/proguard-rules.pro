# Shizuku instantiates this Binder by its exact class name in a separate shell
# process. Renaming or removing its public no-arg constructor breaks binding.
-keep class foldtomaton.boardercoder.com.foldtomaton.FoldtomatonShellService {
    public <init>();
    *;
}
-keep class foldtomaton.boardercoder.com.foldtomaton.FoldtomatonShellService$* { *; }
