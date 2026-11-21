/*
 * Minimal RLBox wasm2c sandbox entry point.
 * The generated WebAssembly module is not a standalone application.
 */
int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    __builtin_trap();
}
