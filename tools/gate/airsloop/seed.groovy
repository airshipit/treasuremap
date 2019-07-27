
pipelineJob('airsloop') {

    displayName('Airsloop')
    description('Bare-metal minimalistic deployment pipeline')

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
        gerritTrigger {
            serverName('OS-CommunityGerrit')
            silentMode(true)

            gerritProjects {
                gerritProject {
                    compareType('PLAIN')
                    pattern("airship/treasuremap")
                    branches {
                        branch {
                            compareType("ANT")
                            pattern("**")
                        }
                    }
                    disableStrictForbiddenFileVerification(false)

                    filePaths {
                        filePath {
                            compareType('ANT')
                            pattern('global/**')
                        }
                        filePath {
                            compareType('ANT')
                            pattern('type/sloop/**')
                        }
                        filePath {
                            compareType('ANT')
                            pattern('site/airsloop/**')
                        }
                        filePath {
                            compareType('ANT')
                            pattern('tools/**')
                        }
                    }
                }
            }

            triggerOnEvents {
                patchsetCreated {
                    excludeDrafts(false)
                    excludeTrivialRebase(false)
                    excludeNoCodeChange(false)
                }
                commentAddedContains {
                    commentAddedCommentContains('recheck')
                }
            }

            cron('H H * * *')
        }

        definition {
            cps {
                script(readFileFromWorkspace("tools/gate/airsloop/Jenkinsfile"))
                sandbox(false)
            }
        }
    }
}

