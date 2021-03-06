module benchd.benchd;

import core.time;
import std.range : isRandomAccessRange, SortedRange;
import std.traits : isInstanceOf;


/** Set options to control the behavior of the benchmark function. */
struct BenchmarkOptions {
    /** The number of iterations of the function to execute prior to
        beginning the benchmark. */
    int warmupIterations = 10;
    /** The number of times to execute the function to benchmark. */
    int benchIterations = 100;
}


/** Prevent the passed items from being optimized out of the loop/benchmark. */
void keepThis(OBJ...)(ref OBJ objs) {
    import core.thread : getpid;
    foreach (obj; objs) {
        if (getpid == 1) obj = obj.init;
    }
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
    BenchmarkOptions run = { warmupIterations: 0, benchIterations: 10 };

    auto results = run.benchmark!(testFunction)();

    assert(results.runTimes.length == 10);
    assert(results.max > Duration.min);
    assert(results.min > Duration.min);
    assert(results.mean > Duration.min);
    assert(results.median > Duration.min);
    assert(results.stdDev >= 0.0);
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
        keepThis(param1, param2);
        // Code goes here...
    }

    BenchmarkOptions run = { warmupIterations: 5, benchIterations: 10 };
    auto results = run.benchmark!(funcToTest)("text parameter", 16);

    // Or pass an anonymous function.
    results = run.benchmark!(
        (string param1, int param2) {
            keepThis(param1, param2);
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
    Duration median = Duration.min;
    float stdDev = -1.0;
}


/** Collect statistics concerning the results.

    Return the min, max, and mean durations and the standard deviation of the
    input values.
*/
auto collectStatistics(Duration[] results) {
    import std.algorithm.comparison : max, min;
    import std.algorithm.iteration : fold;
    import std.algorithm.sorting : sort;

    auto maxmin = fold!(max, min)(results);
    auto meanAndStdDev = meanAndStandardDeviation(results);
    auto median_ = results.sort().median();

    Statistics stats = {
        runTimes: results,
        max: maxmin[0],
        min: maxmin[1],
        mean: meanAndStdDev[0],
        median: median_,
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


@("Calculate the median values of a sorted range's elements.")
unittest {
    import std.range : assumeSorted;
    long[] a = [1, 2, 2, 3, 4, 5, 7];
    long[] b = [1, 2, 2, 3, 5, 5, 5, 7];

    assert(median(a.assumeSorted) == 3);
    assert(median(b.assumeSorted) == 4);
}

/** Calculate the median of an array of values. */
auto median(R)(R durations)
        if (isRandomAccessRange!R && isInstanceOf!(SortedRange, R)) {

    if (durations.length == 1) return durations[0];

    auto firstLoc = durations.length / 2;
    auto first = durations[firstLoc];

    if (durations.length % 2 != 0) {
        return first;
    }
    auto second = durations[firstLoc - 1];
    return ((first + second) / 2);
}


@("toJsonString serializes a Statistics object without loss of data.")
unittest {
    import std.json : parseJSON;

    Statistics results = {
        runTimes: [
            8381.dur!"hnsecs",
            3474.dur!"hnsecs",
            3478.dur!"hnsecs",
            3478.dur!"hnsecs",
            3200.dur!"hnsecs",
            2658.dur!"hnsecs",
            2654.dur!"hnsecs",
            2654.dur!"hnsecs",
            2658.dur!"hnsecs",
            2674.dur!"hnsecs"
        ],
        max: 8318.dur!"hnsecs",
        min: 2654.dur!"hnsecs",
        mean: 3530.dur!"hnsecs",
        stdDev: 1658.36
    };
    auto json = parseJSON(results.toJsonString);

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

    // TODO: Do this efficiently.
    char[] json = cast(char[])"{";
    json ~= `"runs":[`;
    foreach (time; stats.runTimes) {
        json ~= "%s,".format(time.total!"hnsecs");
    }
    json[$-1] = ']';
    json ~= ",";

    json ~= `"max":%s,`.format(stats.max.total!"hnsecs");
    json ~= `"min":%s,`.format(stats.min.total!"hnsecs");
    json ~= `"mean":%s,`.format(stats.mean.total!"hnsecs");
    json ~= `"stdDev":%f`.format(stats.stdDev);

    json ~= "}";
    return cast(string)json;
}

version(unittest) {
    bool approxEqual(double a, double b, double delta = 0.001) {
        return (a + delta > b) && (b + delta > a);
    }
}
