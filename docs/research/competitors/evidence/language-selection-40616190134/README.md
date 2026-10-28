# Canceled setup: language selection probe 40616190134

[Run](https://github.com/negentropi/roma-just-talk/actions/runs/40616190134) at `c41d72fcc83913754206fb7384a20f6be311ddf1` was canceled after static dependencies and cache saving succeeded, while the combined build/native step was in progress. No artifact was downloaded and no picker outcome is claimed.

The actual parallel controls check had exposed coverage files entering its guarded source CWD. The [cancellation receipt](cancellation.json) records the bounded test setup retry: explicit owned profile output and native CWD in `2ebdfd1772e3f45f9fe1fe4e2787af7fbfc53ea2`, tested by run 40617652407 on the same temporary CI ref.
