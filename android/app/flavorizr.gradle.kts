import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("channel")

    productFlavors {
        create("stable") {
            dimension = "channel"
            applicationId = "dev.nploetz.noctua"
            resValue(type = "string", name = "app_name", value = "Noctua")
        }
        create("beta") {
            dimension = "channel"
            applicationId = "dev.nploetz.noctua.beta"
            resValue(type = "string", name = "app_name", value = "Noctua Beta")
        }
    }

    buildFeatures.resValues = true
}