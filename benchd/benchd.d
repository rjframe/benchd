module benchd.benchd;

import core.time;


/** Set options to control the behavior of the benchmark function. */
struct BenchmarkOptions {
    /** The number of iterations of the function to execute prior to
        beginning the benchmark. */
    int warmupIterations = 10;
    /** The number of times to execute the function to benchmark. */
    int benchIterations = 100;
}


@("benchmark runs the function provided to it.")
unittest {
    bool funcHasRun = false;
    void testFunction() { funcHasRun = true; }
    BenchmarkOptions run = { warmupIterations: 0, benchIterations: 1 };

    run.benchmark!(testFunction)();
    assert(funcHasRun == true);
}

@("benchmark runs the function the specified number of times.")
unittest {
    int numberOfRuns = 0;
    void testFunction() { ++numberOfRuns; }
    BenchmarkOptions run = { warmupIterations: 0, benchIterations: 10 };

    run.benchmark!(testFunction)();
    assert(numberOfRuns == 10);
}

@("benchmark returns a set of benchmark results.")
unittest {
    int counter = 0;
    void testFunction() { for (int i; i < 1000; ++i) ++counter; }
    BenchmarkOptions run = { warmupIterations: 1, benchIterations: 10 };

    auto results = run.benchmark!(testFunction)();

    assert(results.runTimes.length == 10);
    assert(results.max > Duration.min);
    assert(results.min > Duration.min);
    assert(results.mean > Duration.min);
    assert(results.stdDev > 0.0);
}

@("benchmark runs warmup iterations before testing.")
unittest {
    int numberOfRuns = 0;
    void testFunction() { ++numberOfRuns; }
    BenchmarkOptions run = { warmupIterations: 5, benchIterations: 1 };

    auto results = run.benchmark!(testFunction)();
    assert(numberOfRuns == 6);
    assert(results.runTimes.length == 1);
}

/** Benchmark the execution time of a function.

    Params:
        options = Options to control the benchmark behavior.
        args = The argumment list to pass to the function.

    Template_Parameters:
        func = the function, delegate, or other callable to test.

    Note:
        Passing `options` via UFCS separates the benchmark options from
        arguments to the function under test for easier readability.
*/
auto benchmark(alias func, ARGS...)(BenchmarkOptions options, ARGS args) in {
    assert(options.warmupIterations >= 0);
    assert(options.benchIterations > 0);
} body {
    foreach (i; 0 .. options.warmupIterations) func(args);

    Duration[] results;
    results.reserve(options.benchIterations);

    foreach (i; 0 .. options.benchIterations) {
        auto start = MonoTime.currTime();
        func(args);
        auto end = MonoTime.currTime();
        results ~= end - start;
    }

    return collectStatistics(results);
}

@("Documentation example for the benchmark function.")
///
unittest {
    void funcToTest(string param1, int param2) {
        // Code goes here...
    }

    BenchmarkOptions run = { warmupIterations: 5, benchIterations: 10 };
    auto results = run.benchmark!(funcToTest)("text parameter", 16);

    // Or pass an anonymous function.
    results = run.benchmark!(
        (string param1, int param2) {
            // Code goes here...
        }
    )("text parameter", 16);
}


/** Container for all benchmark statistics.

    Note:
        Durations are initialized at Duration.min (a negative value).
*/
struct Statistics {
    Duration[] runTimes;
    Duration max = Duration.min;
    Duration min = Duration.min;
    Duration mean = Duration.min;
    float stdDev = 0.0;
}


/** Collect statistics concerning the results.

    Return the min, max, and mean durations and the standard deviation of the
    input values.
*/
auto collectStatistics(Duration[] results) {
    import std.algorithm.comparison : max, min;
    import std.algorithm.iteration : fold;

    auto maxmin = fold!(max, min)(results);
    auto meanAndStdDev = meanAndStandardDeviation(results);

    Statistics stats = {
        runTimes: results,
        max: maxmin[0],
        min: maxmin[1],
        mean: meanAndStdDev[0],
        stdDev: meanAndStdDev[1]
    };
    return stats;
}


@("meanAndStandardDeviation calculates the mean of durations.")
unittest {
    auto durations = [
        1024.dur!"hnsecs",
        1000.dur!"hnsecs",
        54321.dur!"hnsecs"
    ];

    auto mean = meanAndStandardDeviation(durations)[0];
    assert(mean == 18781.dur!"hnsecs");
}

@("meanAndStandardDeviation calculates the standard deviation of durations.")
unittest {
    auto durations = [
        3.dur!"hnsecs",
        6.dur!"hnsecs",
        9.dur!"hnsecs"
    ];

    auto stddev = meanAndStandardDeviation(durations)[1];
    assert(approxEqual(stddev, 2.449));
}

/** Calculate the mean and standard deviation of an array of Durations.

    Returns:
        A tuple of (mean, standard deviation).
*/
auto meanAndStandardDeviation(Duration[] durations) {
    import std.algorithm.iteration : map, fold;
    import std.array : array;
    import std.math : sqrt;
    import std.typecons : tuple;

    auto sums = durations
        .map!(a => a.total!"hnsecs")
        .fold!("a+b", "a + b*b")(tuple(0L, 0L))
        .array;

    auto mean = sums[0] / durations.length;
    auto stddev = sqrt((cast(float)sums[1] / durations.length) - mean*mean);

    return tuple(mean.dur!"hnsecs", stddev);
}


@("toJsonString serializes a Statistics object without loss of data.")
unittest {
    import std.json : parseJSON;

    int counter = 0;
    void testFunction() { for (int i; i < 100; ++i) ++counter; }
    BenchmarkOptions run = { warmupIterations: 0, benchIterations: 10 };
    auto results = run.benchmark!(testFunction)();

    auto json = parseJSON(results.toJsonString);
    assert(json["scale"].str == "hnsecs");
    with(results) {
        auto runs = json["runs"].array;
        for (int i = 0; i < runTimes.length; ++i)
            assert(runs[i].integer == runTimes[i].total!"hnsecs");

        assert(json["max"].integer == max.total!"hnsecs");
        assert(json["min"].integer == min.total!"hnsecs");
        assert(json["mean"].integer == mean.total!"hnsecs");
        assert(approxEqual(json["stdDev"].floating, stdDev));
    }
}

/** Convert a Statistics object to a JSON string. */
string toJsonString(Statistics stats) {
    import std.format : format;

    enum Scale {
        secs = "seconds",
        msecs = "msecs",
        usecs = "usecs",
        hnsecs = "hnsecs"
    }

    auto scale =
        stats.min >= 1.dur!"seconds" ? Scale.secs
        : stats.min >= 1.dur!"msecs" ? Scale.msecs
        : stats.min >= 1.dur!"usecs" ? Scale.usecs
        : Scale.hnsecs;

    long multiplier =
       scale == Scale.usecs ? 10
       : scale == Scale.msecs ? 10_000
       : scale == Scale.secs ? 10_000_000
       : 1;

    // TODO: Do this efficiently.
    char[] json = cast(char[])"{";
    json ~= `"scale":"%s",`.format(scale);
    json ~= `"runs":[`;
    foreach (time; stats.runTimes) {
        json ~= "%s,".format(time.total!"hnsecs" * multiplier);
    }
    json[$-1] = ']';
    json ~= ",";

    json ~= `"max":%s,`.format(stats.max.total!"hnsecs" * multiplier);
    json ~= `"min":%s,`.format(stats.min.total!"hnsecs" * multiplier);
    json ~= `"mean":%s,`.format(stats.mean.total!"hnsecs" * multiplier);
    json ~= `"stdDev":%f`.format(stats.stdDev);

    json ~= "}";
    return cast(string)json;
}

version(unittest) {
    bool approxEqual(double a, double b, double delta = 0.001) {
        return (a + delta > b) && (b + delta > a);
    }
}
