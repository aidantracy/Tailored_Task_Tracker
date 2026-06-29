describe('Sign Up Flow', () => {
    beforeEach(() => {
        cy.intercept('POST', '/signup').as('signupRequest');

        cy.visit('/');
    });

    it('allows a new user to sign up and see the dashboard', () => {
        cy.contains('h1', 'Welcome!').should('be.visible');
        cy.get('[data-cy="signup-modal-button"]').should('be.visible');

        cy.get('[data-cy="signup-modal-button"]').click();

        const uniqueEmail = `testuser@example.com`;
        cy.get('[data-cy="first-name"]').type('John');
        cy.get('[data-cy="last-name"]').type('Doe');
        cy.get('[data-cy="signup-email"]').type(uniqueEmail);
        cy.get('[data-cy="signup-password"]').type('StrongPassword123%');
        cy.get('[data-cy="invitation-key"]').type('demo-key-alpha');

        cy.get('[data-cy="security-question"]').select("What is your mother's maiden name?");
        cy.get('[data-cy="security-answer"]').type('Smith');

        cy.get('[data-cy="signup-submit-button"]').click();

        cy.wait('@signupRequest').its('response.statusCode').should('eq', 201);

        cy.url().should('include', '/');

        cy.contains(`span`, 'Populate Financials').should('be.visible');

        cy.get('[data-cy="login-modal-button"]').should('not.exist');
        cy.get('[data-cy="signup-modal-button"]').should('not.exist');
    });
});

describe('Login Flow', () => {
    beforeEach(() => {
        cy.intercept('POST', '/login').as('loginRequest');

        cy.visit('/');
    });

    it('allows a pre-existing user to log in and see the dashboard', () => {
        cy.contains('h1', 'Welcome!').should('be.visible');
        cy.get('[data-cy="login-modal-button"]').should('be.visible');

        cy.get('[data-cy="login-modal-button"]').click();

        cy.get('[data-cy="login-email"]').type('bakir.grbic@u.boisestate.edu');
        cy.get('[data-cy="login-password"]').type('some_password_for_bakir');
        cy.get('[data-cy="login-submit-button"]').click();

        cy.wait('@loginRequest').its('response.statusCode').should('eq', 200);

        cy.url().should('include', '/');

        cy.contains(`span`, 'Populate Financials').should('be.visible');

        cy.get('[data-cy="login-modal-button"]').should('not.exist');
        cy.get('[data-cy="signup-modal-button"]').should('not.exist');
    });

    it('shows an error on invalid credentials', () => {
        cy.get('[data-cy="login-modal-button"]').click();

        cy.get('[data-cy="login-email"]').type('bakir.grbic@u.boisestate.edu');
        cy.get('[data-cy="login-password"]').type('WRONG_PASSWORD');
        cy.get('[data-cy="login-submit-button"]').click();

        cy.wait('@loginRequest').its('response.statusCode').should('eq', 401);

        cy.get('[data-cy="login-form-error"]').should('be.visible')
            .and('contain.text', 'INCORRECT_PASSWORD');

        // Check that we are still on the homepage
        cy.contains('h1', 'Welcome!').should('be.visible');
    });
});