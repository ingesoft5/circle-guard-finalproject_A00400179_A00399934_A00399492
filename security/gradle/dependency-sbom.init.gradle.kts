// HU-14 · Gradle init script: writes a CycloneDX SBOM of the runtime dependencies of every service.
//
// It is NOT part of the build: it is passed on the command line (see security/scan-dependencies.sh), so no
// build.gradle.kts of any service is modified. It resolves `runtimeClasspath`, which is what ends up inside the
// bootJar of each Docker image, with the versions that Spring's dependency management really selects.
//
//   ./gradlew --init-script security/gradle/dependency-sbom.init.gradle.kts cgDependencySbom
//
// Output: services/<service>/build/security/sbom.cdx.json. Each component carries a package URL (purl), which is what
// Trivy matches against the vulnerability database, and a "cg:scope" property: direct (declared by the service or
// by its platform) or transitive.
import org.gradle.api.artifacts.component.ModuleComponentIdentifier
import org.gradle.api.artifacts.result.ResolvedDependencyResult

allprojects {
    if (path.startsWith(":services:")) {
        afterEvaluate {
            tasks.register("cgDependencySbom") {
                group = "security"
                description = "Writes build/security/sbom.cdx.json with the runtime dependencies (HU-14)"
                val output = layout.buildDirectory.file("security/sbom.cdx.json")
                val serviceName = project.name
                doLast {
                    val conf = configurations.findByName("runtimeClasspath")
                        ?: throw GradleException("$serviceName has no runtimeClasspath")
                    val result = conf.incoming.resolutionResult
                    val directIds = result.root.dependencies
                        .filterIsInstance<ResolvedDependencyResult>()
                        .map { it.selected.id }
                        .filterIsInstance<ModuleComponentIdentifier>()
                        .map { "${it.group}:${it.module}:${it.version}" }
                        .toSet()
                    val components = result.allComponents
                        .map { it.id }
                        .filterIsInstance<ModuleComponentIdentifier>()
                        .distinctBy { "${it.group}:${it.module}:${it.version}" }
                        .sortedBy { "${it.group}:${it.module}" }

                    fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")
                    val json = StringBuilder()
                    json.append("{\n  \"bomFormat\": \"CycloneDX\",\n  \"specVersion\": \"1.5\",\n  \"version\": 1,\n")
                    json.append("  \"metadata\": {\"component\": {\"type\": \"application\", \"name\": \"${esc(serviceName)}\", \"version\": \"${esc(project.version.toString())}\"}},\n")
                    json.append("  \"components\": [\n")
                    components.forEachIndexed { i, c ->
                        val scope = if ("${c.group}:${c.module}:${c.version}" in directIds) "direct" else "transitive"
                        val purl = "pkg:maven/${c.group}/${c.module}@${c.version}"
                        json.append("    {\"type\": \"library\", \"group\": \"${esc(c.group)}\", \"name\": \"${esc(c.module)}\", ")
                        json.append("\"version\": \"${esc(c.version)}\", \"purl\": \"${esc(purl)}\", ")
                        json.append("\"properties\": [{\"name\": \"cg:scope\", \"value\": \"$scope\"}]}")
                        json.append(if (i < components.size - 1) ",\n" else "\n")
                    }
                    json.append("  ]\n}\n")
                    val file = output.get().asFile
                    file.parentFile.mkdirs()
                    file.writeText(json.toString())
                    logger.lifecycle("SBOM of $serviceName: ${components.size} components -> $file")
                }
            }
        }
    }
}
