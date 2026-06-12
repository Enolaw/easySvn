import Testing
@testable import EasySvnApp

@Test func collapseRevertRootsGroupsVenvChildren() {
    let paths = [
        "tools/.venv/lib/a.py",
        "tools/.venv/lib/b.py",
        "tools/.venv/pyvenv.cfg"
    ]
    let roots = IgnorePathHelper.collapseRevertRoots(paths: paths)
    #expect(roots == ["tools/.venv"])
}

@Test func ignoreSpecExtractsParentAndPattern() {
    let spec = IgnorePathHelper.ignoreSpec(for: "tools/.venv")
    #expect(spec?.parent == "tools")
    #expect(spec?.pattern == ".venv")
}
