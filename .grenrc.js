module.exports = {
    "ignoreIssuesWith": [
        "duplicate",
        "invalid",
        "not needed",
        "question"
    ],
    "template": {
        "issue": "- [{{text}}]({{url}}) {{name}}",
        "release": '{{body}}',
    },
    "groupBy": {
        "Enhancements:": ["enhancement"],
        "Bug Fixes:": ["bug"]
    }
};
