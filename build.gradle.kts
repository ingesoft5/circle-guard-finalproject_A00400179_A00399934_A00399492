import org.gradle.api.tasks.SourceSetContainer
import org.gradle.testing.jacoco.tasks.JacocoCoverageVerification
import org.gradle.testing.jacoco.tasks.JacocoReport

plugins {
    id("org.springframework.boot") version "3.2.4" apply false
    id("io.spring.dependency-management") version "1.1.4" apply false
    kotlin("jvm") version "1.9.24" apply false
    kotlin("plugin.spring") version "1.9.24" apply false
    kotlin("plugin.jpa") version "1.9.24" apply false
    id("org.sonarqube") version "4.4.1.3373" apply false
}

// HU-04: services whose line coverage must stay at or above the threshold (JaCoCo verification).
val coreServices = listOf(
    "circleguard-auth-service",
    "circleguard-identity-service",
    "circleguard-promotion-service",
    "circleguard-form-service",
    "circleguard-gateway-service"
)
val minimumLineCoverage = "0.60".toBigDecimal()
// Only the application entry points are left out of the coverage figures; generated Lombok code is
// excluded through lombok.config. No package (model, config, dto...) is excluded wholesale.
val jacocoExcludes = listOf("**/*Application.class")

allprojects {
    group = "com.circleguard"
    version = "1.0.0-SNAPSHOT"

    repositories {
        mavenCentral()
    }
}

subprojects {
    apply(plugin = "java")
    apply(plugin = "org.jetbrains.kotlin.jvm")
    apply(plugin = "jacoco")
    apply(plugin = "org.sonarqube")
    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    dependencies {
        "implementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "testImplementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "compileOnly"("org.projectlombok:lombok")
        "annotationProcessor"("org.projectlombok:lombok")
        "testCompileOnly"("org.projectlombok:lombok")
        "testAnnotationProcessor"("org.projectlombok:lombok")
        "implementation"("org.jetbrains.kotlin:kotlin-reflect")
        "testImplementation"("org.springframework.boot:spring-boot-starter-test")
        "testRuntimeOnly"("com.h2database:h2")
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
        kotlinOptions {
            freeCompilerArgs = listOf("-Xjsr305=strict")
            jvmTarget = "21"
        }
    }

    tasks.named<Test>("test") {
        filter { excludeTestsMatching("*IntegrationTest") }
        finalizedBy("jacocoTestReport")
    }

    // Unit coverage gate: the report is followed by the verification, so `gradle test` already fails
    // (and so does the Jenkins pipeline) when a core service drops below the minimum.
    tasks.named("jacocoTestReport") { finalizedBy("jacocoTestCoverageVerification") }
    tasks.named("check") { dependsOn("jacocoTestCoverageVerification") }
    tasks.withType<JacocoCoverageVerification>().configureEach {
        isEnabled = project.name in coreServices
        violationRules {
            rule {
                element = "BUNDLE"
                limit {
                    counter = "LINE"
                    value = "COVEREDRATIO"
                    minimum = minimumLineCoverage
                }
            }
        }
    }
    // Lazy: the compiled-classes directories (Java and Kotlin) are resolved when the task runs.
    val mainClassTrees = extensions.getByType<SourceSetContainer>()["main"].output.classesDirs.elements.map { dirs ->
        dirs.map { fileTree(it.asFile) { exclude(jacocoExcludes) } }
    }
    tasks.withType<JacocoReport>().configureEach { classDirectories.setFrom(files(mainClassTrees)) }
    tasks.withType<JacocoCoverageVerification>().configureEach { classDirectories.setFrom(files(mainClassTrees)) }

    val testSourceSet = extensions.getByType<SourceSetContainer>()["test"]

    tasks.register<Test>("integrationTest") {
        group = "verification"
        description = "Runs *IntegrationTest classes"
        testClassesDirs = testSourceSet.output.classesDirs
        classpath = testSourceSet.runtimeClasspath
        filter {
            includeTestsMatching("*IntegrationTest")
            isFailOnNoMatchingTests = false
        }
        // The 10k-node benchmark (tag "performance") is timing-sensitive; run it with -PwithPerformance.
        if (!project.hasProperty("withPerformance")) {
            useJUnitPlatform { excludeTags("performance") }
        }
        shouldRunAfter("test")
    }

    tasks.withType<JacocoReport> {
        reports {
            xml.required.set(true)
            html.required.set(true)
        }
    }

    tasks.withType<Test> {
        useJUnitPlatform()
        // Testcontainers 1.19 negotiates an old Docker API and Docker Engine 29 only accepts 1.44 or newer.
        systemProperty("api.version", "1.44")
        maxHeapSize = "768m"
        testLogging {
            events("failed")
            exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        }
        // HU-01: application.yml no longer ships secrets. Tests get ephemeral random values that
        // are never persisted; a value already exported in the environment takes precedence.
        val random = java.security.SecureRandom()
        fun randomHex(bytes: Int) = ByteArray(bytes).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        listOf("CG_JWT_SECRET" to 32, "CG_QR_SECRET" to 32, "CG_VAULT_SECRET" to 32, "CG_VAULT_SALT" to 8, "CG_VAULT_HASH_SALT" to 8)
            .filter { (name, _) -> System.getenv(name) == null }
            .forEach { (name, bytes) -> environment(name, randomHex(bytes)) }
    }
}

// HU-04: prints (and saves in build/reports/coverage-summary.md) the line coverage of the core services,
// read from the JaCoCo XML reports. Run it after `gradle test`.
tasks.register("coverageSummary") {
    group = "verification"
    description = "Summarises the JaCoCo line coverage of the core services"
    mustRunAfter(coreServices.map { ":services:$it:jacocoTestReport" })
    val reports = coreServices.associateWith { file("services/$it/build/reports/jacoco/test/jacocoTestReport.xml") }
    val output = layout.buildDirectory.file("reports/coverage-summary.md")
    doLast {
        val factory = javax.xml.parsers.DocumentBuilderFactory.newInstance()
        factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
        val lines = mutableListOf(
            "| Service | Covered lines | Total lines | Line coverage | Minimum |",
            "|---|---|---|---|---|"
        )
        reports.forEach { (service, xml) ->
            if (!xml.exists()) {
                lines += "| $service | - | - | no report | ${minimumLineCoverage.multiply(java.math.BigDecimal(100)).toInt()} % |"
                return@forEach
            }
            val root = factory.newDocumentBuilder().parse(xml).documentElement
            val children = root.childNodes
            var missed = 0
            var covered = 0
            for (i in 0 until children.length) {
                val node = children.item(i)
                if (node is org.w3c.dom.Element && node.tagName == "counter" && node.getAttribute("type") == "LINE") {
                    missed = node.getAttribute("missed").toInt()
                    covered = node.getAttribute("covered").toInt()
                }
            }
            val total = missed + covered
            val percent = if (total == 0) 0.0 else 100.0 * covered / total
            val verdict = if (percent >= minimumLineCoverage.toDouble() * 100) "OK" else "BELOW"
            lines += "| $service | $covered | $total | ${"%.1f".format(percent)} % ($verdict) | ${minimumLineCoverage.multiply(java.math.BigDecimal(100)).toInt()} % |"
        }
        val text = lines.joinToString("\n")
        println(text)
        output.get().asFile.also { it.parentFile.mkdirs() }.writeText(text + "\n")
    }
}
