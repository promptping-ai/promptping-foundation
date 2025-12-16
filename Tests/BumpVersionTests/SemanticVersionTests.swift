import BumpVersion
import Testing

@Suite("SemanticVersion Tests")
struct SemanticVersionTests {

  @Suite("Parsing")
  struct ParsingTests {

    @Test("Parse simple version")
    func parseSimple() {
      let version = SemanticVersion.parse("1.2.3")
      #expect(version?.major == 1)
      #expect(version?.minor == 2)
      #expect(version?.patch == 3)
      #expect(version?.isStable == true)
    }

    @Test("Parse version with v prefix")
    func parseWithVPrefix() {
      let version = SemanticVersion.parse("v2.0.0")
      #expect(version?.major == 2)
      #expect(version?.minor == 0)
      #expect(version?.patch == 0)
    }

    @Test("Parse version with alpha prerelease")
    func parseAlpha() {
      let version = SemanticVersion.parse("1.0.0-alpha.1")
      #expect(version?.major == 1)
      #expect(version?.minor == 0)
      #expect(version?.patch == 0)
      #expect(version?.preRelease == "alpha.1")
      #expect(version?.isPreRelease == true)
    }

    @Test("Parse version with beta prerelease")
    func parseBeta() {
      let version = SemanticVersion.parse("3.2.1-beta.5")
      #expect(version?.preRelease == "beta.5")
    }

    @Test("Parse version with rc prerelease")
    func parseRc() {
      let version = SemanticVersion.parse("2.0.0-rc.2")
      #expect(version?.preRelease == "rc.2")
    }

    @Test("Invalid version returns nil")
    func parseInvalid() {
      #expect(SemanticVersion.parse("invalid") == nil)
      #expect(SemanticVersion.parse("1.2") == nil)
      #expect(SemanticVersion.parse("1.2.3.4") == nil)
      #expect(SemanticVersion.parse("") == nil)
    }
  }

  @Suite("Bumping")
  struct BumpingTests {

    @Test("Bump major resets minor and patch")
    func bumpMajor() {
      let version = SemanticVersion(1, 5, 3)
      let bumped = version.bumpMajor()
      #expect(bumped.major == 2)
      #expect(bumped.minor == 0)
      #expect(bumped.patch == 0)
      #expect(bumped.isStable == true)
    }

    @Test("Bump minor resets patch")
    func bumpMinor() {
      let version = SemanticVersion(1, 5, 3)
      let bumped = version.bumpMinor()
      #expect(bumped.major == 1)
      #expect(bumped.minor == 6)
      #expect(bumped.patch == 0)
    }

    @Test("Bump patch increments patch only")
    func bumpPatch() {
      let version = SemanticVersion(1, 5, 3)
      let bumped = version.bumpPatch()
      #expect(bumped.major == 1)
      #expect(bumped.minor == 5)
      #expect(bumped.patch == 4)
    }
  }

  @Suite("Prerelease")
  struct PrereleaseTests {

    @Test("Add alpha prerelease")
    func addAlpha() {
      let version = SemanticVersion(1, 0, 0)
      let alpha = version.withPrerelease(.alpha)
      #expect(alpha.description == "1.0.0-alpha.1")
    }

    @Test("Add beta prerelease with custom number")
    func addBetaWithNumber() {
      let version = SemanticVersion(2, 0, 0)
      let beta = version.withPrerelease(.beta, number: 3)
      #expect(beta.description == "2.0.0-beta.3")
    }

    @Test("Bump existing prerelease increments number")
    func bumpExistingPrerelease() {
      let version = SemanticVersion(1, 0, 0, "alpha.2")
      let bumped = version.bumpPrerelease(.alpha)
      #expect(bumped.preRelease == "alpha.3")
    }

    @Test("Bump different prerelease type starts at 1")
    func bumpDifferentPrereleaseType() {
      let version = SemanticVersion(1, 0, 0, "alpha.5")
      let bumped = version.bumpPrerelease(.beta)
      #expect(bumped.preRelease == "beta.1")
    }

    @Test("Release removes prerelease")
    func release() {
      let version = SemanticVersion(1, 0, 0, "rc.1")
      let released = version.release()
      #expect(released.isStable == true)
      #expect(released.description == "1.0.0")
    }
  }

  @Suite("Description")
  struct DescriptionTests {

    @Test("Simple version description")
    func simpleDescription() {
      let version = SemanticVersion(1, 2, 3)
      #expect(version.description == "1.2.3")
    }

    @Test("Prerelease version description")
    func prereleaseDescription() {
      let version = SemanticVersion(1, 0, 0, "alpha.1")
      #expect(version.description == "1.0.0-alpha.1")
    }
  }

  @Suite("Equality")
  struct EqualityTests {

    @Test("Equal versions")
    func equalVersions() {
      let v1 = SemanticVersion(1, 2, 3)
      let v2 = SemanticVersion(1, 2, 3)
      #expect(v1 == v2)
    }

    @Test("Different versions")
    func differentVersions() {
      let v1 = SemanticVersion(1, 2, 3)
      let v2 = SemanticVersion(1, 2, 4)
      #expect(v1 != v2)
    }

    @Test("Equal prereleases")
    func equalPrereleases() {
      let v1 = SemanticVersion(1, 0, 0, "alpha.1")
      let v2 = SemanticVersion(1, 0, 0, "alpha.1")
      #expect(v1 == v2)
    }
  }

  @Suite("Comparison")
  struct ComparisonTests {

    @Test("Major version comparison")
    func compareMajor() {
      let v1 = SemanticVersion(1, 0, 0)
      let v2 = SemanticVersion(2, 0, 0)
      #expect(v1 < v2)
    }

    @Test("Minor version comparison")
    func compareMinor() {
      let v1 = SemanticVersion(1, 1, 0)
      let v2 = SemanticVersion(1, 2, 0)
      #expect(v1 < v2)
    }

    @Test("Patch version comparison")
    func comparePatch() {
      let v1 = SemanticVersion(1, 0, 1)
      let v2 = SemanticVersion(1, 0, 2)
      #expect(v1 < v2)
    }

    @Test("Prerelease comes before stable")
    func prereleaseBeforeStable() {
      let prerelease = SemanticVersion(1, 0, 0, "alpha.1")
      let stable = SemanticVersion(1, 0, 0)
      #expect(prerelease < stable)
    }
  }
}
