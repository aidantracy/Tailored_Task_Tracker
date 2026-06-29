# Process Tracker

A Kanban-style finance task tracker (Flask + MySQL) built as a team capstone project.

<!-- Badge -->
![Build and Test](https://github.com/aidantracy/Tailored_Task_Tracker/actions/workflows/ci.yml/badge.svg)


## Testing

### Prereqs for local testing
The following installs both dev and prod deps:
```shell
npm install
```

To install python requirements use the following:
I'd recommend using a python environment  manager like conda or whichever
you'd prefer before running the following!
```shell
pip install ".[dev]"
```

For running end-to-end tests using Cypress you must have project containers
running in the background.

If needed:
```shell
podman machine start
```

Then start the containers:
```shell
podman compose up -d --build 
```

To fully clean up:
```shell
podman compose down -v --rmi all
```

or use the clean.sh script below.
```shell
# Tear down this project (current behavior):

./clean.sh


# Also prune unused stuff (safe):

PRUNE_UNUSED=1 ./clean.sh


# Delete all images on the machine (stops/removes all containers first):

NUKE_IMAGES=1 ./clean.sh


# Factory reset (images, containers, networks, volumes, build cache):

NUKE_ALL=1 ./clean.sh
```




### To run pytest tests
```shell
pytest
```

### To run QUnit tests
```shell
npm test
```

### To run Cypress E2E
For just the cli:
```shell
npm run cypress:run 
```

To see it in the Cypress app in a browswer:
```shell
npm run cypress:open 
```
1. Then choose e2e testing
2. Choose whichever browser you want
3. Start e2e testing
4. In the specs tab, click the e2e test, like `auth.cy.js`
5. It should now run it in a mini browser so you can see whats happening!






