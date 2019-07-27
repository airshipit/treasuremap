
pipelineJob('Seaworthy') {

    displayName('Seaworthy')
    description('Bare-metal continuous deployment pipeline')

    logRotator {
        daysToKeep(30)
    }

    parameters {
        string {
            defaultValue("uplift")
            description("Reference to treasuremap, e.g. refs/changes/12/12345/12")
            name("AIRSHIP_MANIFESTS_REF")
            trim(true)
        }
        booleanParam {
            defaultValue(true)
            description('Flag to publish the console log from the pipeline run to artifactory. ' +
                        'Set this value to false, if you should want to suppress uploading ' +
                        'and publishing of the pipeline logs to the artifactory.')
            name("ARTIFACTORY_LOGS")
        }

    }

    concurrentBuild(false)

    triggers {

            cron('H H * * *')
        }

        definition {
            cpsScm {
                scm {
                    git('https://review.opendev.org/airship/treasuremap')
                    scriptPath('tools/gate/seaworthy/Jenkinsfile')
                    lightweight(true)
                }
            }
        }
    }
}

