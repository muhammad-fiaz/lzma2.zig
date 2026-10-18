$targets = @(
    'x86_64-windows',
    'x86-windows',
    'x86_64-linux-gnu',
    'x86-linux-musl',
    'aarch64-linux-musl',
    'arm-linux-musleabihf',
    'riscv32-linux-musl',
    'aarch64-macos',
    'x86_64-macos',
    'x86-freestanding'
)

$rootDir = Get-Location

foreach ($t in $targets) {
    Write-Host ">>> Cross-compiling target ${t} for lzma2.zig..."
    Set-Location $rootDir
    zig build "-Dtarget=$t"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build lzma2.zig for $t"
        exit 1
    }

    $xzDir = Join-Path $rootDir "xz.zig"
    if (Test-Path $xzDir) {
        Write-Host ">>> Cross-compiling target ${t} for xz.zig..."
        Set-Location $xzDir
        zig build "-Dtarget=$t"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to build xz.zig for $t"
            exit 1
        }
    }

    Write-Host ">>> Target ${t}: PASS"
}

Set-Location $rootDir
Write-Host "All 10 target triples compiled successfully without error!"
