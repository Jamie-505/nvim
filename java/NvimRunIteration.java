// Runs exactly one invocation of a parameterized (or other template) test
// through the JUnit Platform launcher, for neotest's `[n]` children:
//
//   java <test task jvm args> -cp <test runtime classpath> NvimRunIteration.java \
//     <class, '.' or '$' for nested> <method name> <zero-based invocation index>
//
// Prints one `NVIM_RESULT <status>\t<uniqueId>\t<displayName>` line per test it
// executed, then `NVIM_FAILURE` blocks with the stack trace of each failure.
// Exit code: 0 all passed, 1 a test failed, 2 nothing ran, 3 bad arguments.
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectIteration;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectMethod;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.launcher.TestExecutionListener;
import org.junit.platform.launcher.TestIdentifier;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;

public class NvimRunIteration {
    // `a.b.Outer.Inner` → `a.b.Outer$Inner`, trying from the right
    static Class<?> load(String name) throws ClassNotFoundException {
        String candidate = name;
        while (true) {
            try {
                return Class.forName(candidate, false, NvimRunIteration.class.getClassLoader());
            } catch (ClassNotFoundException e) {
                int dot = candidate.lastIndexOf('.');
                if (dot < 0) throw e;
                candidate = candidate.substring(0, dot) + '$' + candidate.substring(dot + 1);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("usage: NvimRunIteration <class> <method> <index>");
            System.exit(3);
        }
        Class<?> type = load(args[0]);
        List<Method> named = new ArrayList<>();
        for (Method m : type.getDeclaredMethods()) {
            if (m.getName().equals(args[1]) && !m.isSynthetic()) named.add(m);
        }
        if (named.size() != 1) {
            System.err.println("expected one method " + args[1] + " in " + type.getName() + ", found " + named.size());
            System.exit(3);
        }
        var selector = selectIteration(selectMethod(type, named.get(0)), Integer.parseInt(args[2]));
        var request = LauncherDiscoveryRequestBuilder.request().selectors(selector).build();
        List<String> results = new ArrayList<>();
        List<String> failures = new ArrayList<>();
        boolean[] failed = {false};
        TestExecutionListener listener = new TestExecutionListener() {
            @Override
            public void executionFinished(TestIdentifier id, TestExecutionResult r) {
                if (!id.isTest()) return;
                results.add(r.getStatus() + "\t" + id.getUniqueId() + "\t" + id.getDisplayName());
                if (r.getStatus() != TestExecutionResult.Status.SUCCESSFUL) {
                    failed[0] = true;
                    r.getThrowable().ifPresent(t -> {
                        StringWriter s = new StringWriter();
                        t.printStackTrace(new PrintWriter(s));
                        failures.add(s.toString());
                    });
                }
            }
        };
        LauncherFactory.create().execute(request, listener);
        results.forEach(r -> System.out.println("NVIM_RESULT " + r));
        failures.forEach(f -> System.out.println("NVIM_FAILURE\n" + f + "NVIM_FAILURE_END"));
        System.exit(results.isEmpty() ? 2 : (failed[0] ? 1 : 0));
    }
}
