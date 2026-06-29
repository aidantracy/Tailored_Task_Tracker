const { defineConfig } = require("cypress");

require('dotenv').config();

module.exports = defineConfig({
  e2e: {
    specPattern: 'tests/e2e/**/*.cy.{js,jsx,ts,tsx}',
    supportFile: 'tests/e2e/support/e2e.js',
    fixturesFolder: 'tests/e2e/fixtures',
    baseUrl: 'http://127.0.0.1:5000',
    setupNodeEvents(on, config) {
        config.env.MYSQL_ROOT_PASSWORD = process.env.MYSQL_ROOT_PASSWORD;
        config.env.MYSQL_DATABASE = process.env.MYSQL_DATABASE;

        return config;
    },
  },
});
