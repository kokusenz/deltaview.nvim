# Contributing

Thank you for wanting to improve deltaview.nvim!

You can make contributions in the following ways:

- **Mention it** somehow to help reach broader audience. This helps a lot.
- **Create a GitHub issue**. This can be bug reports, feature requests, or anything you feel like you want in your workflow. Please @kokusenz, as it will help me see it and respond faster.
- **Create a pull request**. Before you do so, please file an issue. This is just so I can be aware and be able to notify in case it is work that's already in progress or cannot be done, so as to not waste anybodies time.

## Workflow recommendations

- **Testing**. I am using mini.test for this project.
    - **Run tests** using `make test` from the root directory, or install mini.test into your configuration to run it. Check out Makefile for additional commands, such as running a specific test.
    - **Property based testing**. I have been doing a pseudo property based testing style for my unit tests. This just means I am writing generators to create lots of inputs, and properties to test the inputs from those generators. At the end of the day, most of my cases are still hard coded, which makes this not fully PBT. 
    - **AI Assistance**. In the .claude directory, there is an ai skill for property based testing that should get picked up automatically if you are using something like claude code or opencode. This skill just helps agents write PBT style tests with lua without a framework dedicated for it.
- **Changelog**. After raising a pr, please update the changelog with a description, a small increment, and the pr link. If any previous changelog entries do not have a commit hash associated but rather a pr link, feel free to update those pr links with the commit hash of the merge.
- **Help Documentation**. Please update any relevant help documentation in doc/deltaview.txt with your change.
