
// Cypress.Commands.add('resetDB', () => {
//     const composeCommand = Cypress.env('COMPOSE_CMD');

//     const dbPassword = Cypress.env('MYSQL_ROOT_PASSWORD');
//     const dbName = Cypress.env('MYSQL_DATABASE');

//     const execCommand = `${composeCommand} exec -T db mysql -uroot -p${dbPassword} ${dbName} < db/init/reset.sql`;


//     cy.exec(execCommand).then((result) => {
//         cy.log('Database reset successfully!');
//         if (result.stderr) {
//             cy.log(`Stderr: ${result.stderr}`);
//         }
//     });
// });


// no dependancy for podman compose - makes it more agnostic between machines. Passed test 10/26
// Leaving previous code commented out, in case this throws errors for MacOS
Cypress.Commands.add('resetDB', () => {
  // We avoid compose entirely. Find the db container by compose labels,
  // then exec inside it and use env vars *inside the container*.
  const engine = Cypress.env('ENGINE') || 'podman';
  const project = Cypress.env('PROJECT_NAME') || '';

  // Get the container ID for the db service under this compose project
  const getId =
    `${engine} ps -q ` +
    (project ? `--filter "label=com.docker.compose.project=${project}" ` : '') +
    `--filter "label=com.docker.compose.service=db" | head -n1`;

  cy.exec(getId).then(({ stdout }) => {
    const id = stdout.trim();
    expect(id, 'db container id').to.match(/^[a-f0-9]+$/i);

    // Run mysql inside the container; read password & db name from env there.
    // Use the reset.sql that's already mounted at /docker-entrypoint-initdb.d/
    const resetCmd =
      `${engine} exec -i ${id} sh -lc ` +
      `'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" < /docker-entrypoint-initdb.d/reset.sql'`;

    return cy.exec(resetCmd, { timeout: 60_000 }).then(({ stderr }) => {
      if (stderr) cy.log(`reset stderr: ${stderr}`);
      cy.log('Database reset successfully!');
    });
  });
});
