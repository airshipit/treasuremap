
pipelineJob('airship-seaworthy') {

    displayName('Airship Seaworthy')
    description('Bare-metal continuous deployment pipeline')

    logRotator {
        daysToKeep(30)
    }

    parameters {
        string {
            defaultValue("uplift")
            description("Reference to airship-treasuremap, e.g. refs/changes/12/12345/12")
            name("AIRSHIP_MANIFESTS_REF")
            trim(true)
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
                    pattern("openstack/airship-treasuremap")
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
                            pattern('type/**')
                        }
                        filePath {
                            compareType('ANT')
                            pattern('site/**')
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
                script(readFileFromWorkspace("tools/gate/Jenkinsfile"))
                sandbox()
            }
        }
    }
}

