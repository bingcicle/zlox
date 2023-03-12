const std = @import("std");
const VM = @import("vm").VirtualMachine;
const InterpretResult = @import("vm").InterpretResult;

fn runTestPasses(file_name: []const u8) !void {
    const allocator = std.testing.allocator;
    var vm = try VM.init(allocator, true);
    defer vm.deinit();

    var result = try vm.runFile(file_name);

    try std.testing.expectEqual(InterpretResult.ok, result);
}

fn runTestFails(file_name: []const u8) !void {
    const allocator = std.testing.allocator;
    var vm = try VM.init(allocator, true);
    defer vm.deinit();

    var result = try vm.runFile(file_name);

    try std.testing.expectEqual(InterpretResult.compile_error, result);
}

test "smoke test" {
    // try runTest("./tests/data/22_scope.lox");
}

test "all" {
    try runTestPasses("./tests/data/18_types.lox");
    try runTestPasses("./tests/data/19_strings.lox");
    try runTestPasses("./tests/data/21_global_variables.lox");
    try runTestPasses("./tests/data/22_scope.lox");
}

test "for" {
    // [line 2] Error at 'var': Expect expression.
    try runTestFails("./tests/data/for/var_in_body.lox");

    // [line 2] Error at 'class': Expect expression.
    try runTestFails("./tests/data/for/class_in_body.lox");

    // [line 3] Error at '{': Expect expression.
    // [line 3] Error at ')': Expect ';' after expression.
    try runTestFails("./tests/data/for/statement_condition.lox");

    // [line 2] Error at '{': Expect expression.
    try runTestFails("./tests/data/for/statement_increment.lox");

    // [line 3] Error at '{': Expect expression.
    // [line 3] Error at ')': Expect ';' after expression.
    try runTestFails("./tests/data/for/statement_initializer.lox");

    // [line 2] Error at 'fun': Expect expression.
    // try runTestFails("./tests/data/for/fun_in_body.lox");

    // try runTestPasses("./tests/data/for/scope.lox");
}
