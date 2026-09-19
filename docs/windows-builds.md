# Windows native build commissioning

The work Ubuntu bootstrap installs cross-binutils for inspecting Windows x64
PE files, and the Rust toolchain in `config/rust-toolchain` alongside the moving
default. It installs `orbstack-windows-build` for commissioning the matching
Parallels VM. Personal machines do not receive this tooling.

Create or restore Windows separately on the work mini, activate Parallels and
install Git for Windows, rustup and Visual Studio 2026 Build Tools with the x64
C++ workload. These Windows applications are prerequisites; the Ubuntu bootstrap
does not install licensed Windows applications or create a Windows VM.

After the running VM is available, run inside the work Ubuntu VM:

```bash
orbstack-windows-build provision
orbstack-windows-build verify
```

Pass the VM name as the second argument when it differs from `Windows 11`.
Provisioning installs the exact Rust version and `x86_64-pc-windows-msvc` target
without changing the Windows default toolchain. Verification runs Rust, checks
the installed target and checks `dumpbin` in the x64 Visual Studio environment.
Rerun this idempotent command after restoring Windows or changing the managed
Rust version. Installing Rust in Linux alone does not install a Windows target.

Work Ubuntu VMs on the same Mac share the `Windows 11` Parallels VM by default.
`bin/dev clone work experiment-name` copies the existing `work-dev` Ubuntu VM,
including its installed tooling and work-profile settings, into
`work-exp-experiment-name`. Fresh provisioning installs the tooling from the
work profile instead. Neither operation creates or clones a Windows VM.

Running `orbstack-windows-build provision` from any of these Ubuntu VMs installs
the pinned Rust toolchain and target in the selected Windows VM. That Windows
environment is shared by every Ubuntu VM using it; an Ubuntu clone does not
isolate Windows toolchain changes. `verify` checks the environment without
installing anything. For a separate Windows build environment, create another
Parallels VM and pass its name to both commissioning commands. Configure the
project's build settings to use that same VM.

Share a transfer directory on the matching Mac with Windows and expose it as a
mapped drive or UNC path supported by the project's build scripts. Keep active
source inside Ubuntu. Configure transfer paths and the Windows VM name in
private project settings. Use temporary source snapshots for transfer and keep
compiler intermediates inside Windows.

From a fresh project checkout, authenticate any private feeds, install the
repository-pinned SDKs and workloads, then follow the project's native dependency
setup instructions. Projects own their dependency versions and source/checksum
verification. Run the project's build and relevant tests; the machine verifier
does not replace these checks.

Windows commands use OrbStack's `mac prlctl` command bridge. They do not use the
Docker API SSH key, which deliberately cannot execute remote shell commands.
No additional SSH grant, guest Docker daemon or macOS compiler installation is
needed. Keep credentials on the coordinator and never put feed tokens in a
`prlctl` command.
