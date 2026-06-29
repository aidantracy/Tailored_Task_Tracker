// ui.js — admin nav + signup/login modal loader + tiny helpers

export function initAdminNavListeners() {
  const adminNav = document.querySelector('aside nav ul');
  if (!adminNav) return;

  const navLinks = document.querySelectorAll('.nav-link');
  const contentViews = document.querySelectorAll('.content-view');

  navLinks.forEach(link => {
    link.addEventListener('click', function (event) {
      event.preventDefault();
      const targetId = this.getAttribute('data-target');
      const targetView = document.getElementById(targetId);
      contentViews.forEach(view => view.classList.add('hidden'));
      if (targetView) targetView.classList.remove('hidden');
      navLinks.forEach(navLink => navLink.classList.remove('active-link'));
      this.classList.add('active-link');
    });
  });

  const promoteNav = document.getElementById('nav-promote-users');
  if (promoteNav) {
      promoteNav.addEventListener('click', loadCandidates);
  }

  const revokeNav = document.getElementById('nav-revoke-admins');
  if (revokeNav) {
      revokeNav.addEventListener('click', loadAdmins);
  }

  const deleteNav = document.getElementById('nav-delete-users');
  if (deleteNav)  {
      deleteNav.addEventListener('click', loadDeletableUsers);
  }
}


async function loadDeletableUsers() {
    const deleteList = document.getElementById('delete-list');
    const errorMsg = document.getElementById('delete-error');
    const successMsg = document.getElementById('delete-success');

    if(!deleteList) return;

    if(errorMsg) errorMsg.textContent = '';
    if(successMsg) successMsg.textContent = '';
    deleteList.innerHTML = '<tr><td colspan="4" class="px-6 py-4 text-center text-gray-500">Loading users...</td></tr>';

    try {
        const response = await fetch('api/admin/users/active');
        const result = await response.json();

        if (response.ok) {
            renderDeletableUsers(result.data);
        } else {
            deleteList.innerHTML = `<tr><td colspan="4" class="px-6 py-4 text-center text-red-500">Error: ${result.error?.message || 'Failed to load'}</td></tr>`;
        }
    } catch (error) {
        console.error(error);
        deleteList.innerHTML = '<tr><td colspan="4" class="px-6 py-4 text-center text-red-500">Network error occurred.</td></tr>';
    }
}

function renderDeletableUsers(users) {
    const deleteList = document.getElementById('delete-list');
    if (!deleteList) return;

    if (!users || users.length === 0) {
        deleteList.innerHTML = '<tr><td colspan="4" class="px-6 py-4 text-center text-gray-500">No other users found.</td></tr>';
        return;
    }

    deleteList.innerHTML = users.map(user => `
            <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-900">${escapeHtml(user.full_name)}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">${escapeHtml(user.email)}</div>
                </td>
                 <td class="px-6 py-4 whitespace-nowrap">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${user.role === 'Admin' ? 'bg-purple-100 text-purple-800' : 'bg-green-100 text-green-800'}">
                        ${escapeHtml(user.role)}
                    </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <button 
                        class="delete-user-btn bg-red-600 text-white px-3 py-1 rounded hover:opacity-90 transition duration-150 ease-in-out" 
                        data-id="${user.user_id}" 
                        data-name="${escapeHtml(user.full_name)}">
                        Delete
                    </button>
                </td>
            </tr>
        `).join('');

    document.querySelectorAll('.delete-user-btn').forEach(btn => {
        btn.addEventListener('click', handleDeleteUserClick);
    });
}

async function handleDeleteUserClick(e) {
    const btn = e.target;
    const userId = btn.dataset.id;
    const userName = btn.dataset.name;

    const errorMsg = document.getElementById('delete-error');
    const successMsg = document.getElementById('delete-success');

    if (!confirm(`DANGER: Are you sure you want to DELETE ${userName}? They will lose all access immediately.`)) {
        return;
    }

    const originalText = btn.textContent;
    btn.textContent = 'Processing...';
    btn.disabled = true;

    try {
        const response = await fetch(`api/admin/users/delete/${userId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });

        const result = await response.json();

        if (response.ok) {
            if(successMsg) successMsg.textContent = `${userName} was deleted successfully.`;
            if(errorMsg) errorMsg.textContent = '';
            loadDeletableUsers();
        } else {
            if(errorMsg) errorMsg.textContent = result.error?.message || 'Failed to delete.';
            btn.textContent = originalText;
            btn.disabled = false;
        }
    } catch (error) {
        if(errorMsg) errorMsg.textContent = 'Network error occurred.';
        btn.textContent = originalText;
        btn.disabled = false;
    }
}


async function loadAdmins() {
    const adminsList = document.getElementById('admins-list');
    const errorMsg = document.getElementById('revoke-error');
    const successMsg = document.getElementById('revoke-success');

    if(!adminsList) return;

    if(errorMsg) errorMsg.textContent = '';
    if(successMsg) successMsg.textContent = '';
    adminsList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-gray-500">Loading admins...</td></tr>';

    try {
        const response = await fetch('api/admin/users/admins');
        const result = await response.json();

        if (response.ok) {
            renderAdmins(result.data);
        } else {
            adminsList.innerHTML = `<tr><td colspan="3" class="px-6 py-4 text-center text-red-500">Error: ${result.error?.message || 'Failed to load'}</td></tr>`;
        }
    } catch (error) {
        console.error(error);
        adminsList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-red-500">Network error occurred.</td></tr>';
    }
}

function renderAdmins(users) {
    const adminsList = document.getElementById('admins-list');
    if (!adminsList) return;

    if (!users || users.length === 0) {
        adminsList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-gray-500">No other admins found.</td></tr>';
        return;
    }

    adminsList.innerHTML = users.map(user => `
            <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-900">${escapeHtml(user.full_name)}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">${escapeHtml(user.email)}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <button 
                        class="revoke-btn bg-red-600 text-white px-3 py-1 rounded hover:opacity-90 transition duration-150 ease-in-out" 
                        data-id="${user.user_id}" 
                        data-name="${escapeHtml(user.full_name)}">
                        Revoke
                    </button>
                </td>
            </tr>
        `).join('');

    document.querySelectorAll('.revoke-btn').forEach(btn => {
        btn.addEventListener('click', handleRevokeClick);
    });
}

async function handleRevokeClick(e) {
    const btn = e.target;
    const userId = btn.dataset.id;
    const userName = btn.dataset.name;

    const errorMsg = document.getElementById('revoke-error');
    const successMsg = document.getElementById('revoke-success');

    if (!confirm(`Are you sure you want to remove Admin privileges from ${userName}?`)) {
        return;
    }

    const originalText = btn.textContent;
    btn.textContent = 'Processing...';
    btn.disabled = true;

    try {
        const response = await fetch(`api/admin/users/revoke/${userId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });

        const result = await response.json();

        if (response.ok) {
            if(successMsg) successMsg.textContent = `${userName} is no longer an admin.`;
            if(errorMsg) errorMsg.textContent = '';
            loadAdmins();
        } else {
            if(errorMsg) errorMsg.textContent = result.error?.message || 'Failed to revoke.';
            btn.textContent = originalText;
            btn.disabled = false;
        }
    } catch (error) {
        if(errorMsg) errorMsg.textContent = 'Network error occurred.';
        btn.textContent = originalText;
        btn.disabled = false;
    }
}

async function loadCandidates() {
    const candidatesList = document.getElementById('candidates-list');
    const errorMsg = document.getElementById('promote-error');
    const successMsg = document.getElementById('promote-success');

    if(!candidatesList) return;

    candidatesList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-gray-500">Loading users...</td></tr>';

    try {
        const response = await fetch('api/admin/users/candidates');
        const result = await response.json();

        if (response.ok) {
            renderCandidates(result.data);
        } else {
            candidatesList.innerHTML = `<tr><td colspan="3" class="px-6 py-4 text-center text-red-500">Error: ${result.error?.message || 'Failed to load'}</td></tr>`;
        }
    } catch (error) {
        console.error(error);
        candidatesList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-red-500">Network error occurred.</td></tr>';
    }
}

function renderCandidates(users) {
    const candidatesList = document.getElementById('candidates-list');

    if (!users || users.length === 0) {
        candidatesList.innerHTML = '<tr><td colspan="3" class="px-6 py-4 text-center text-gray-500">No eligible users found.</td></tr>';
        return;
    }

    candidatesList.innerHTML = users.map(user => `
            <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm font-medium text-gray-900">${escapeHtml(user.full_name)}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-500">${escapeHtml(user.email)}</div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <button
                        class="promote-btn bg-brand-blue text-white px-3 py-1 rounded hover:opacity-90 transition duration-150 ease-in-out"
                        data-id="${user.user_id}"
                        data-name="${escapeHtml(user.full_name)}">
                        Promote
                    </button>
                </td>
            </tr>
        `).join('');

    // Attach event listeners to new buttons
    document.querySelectorAll('.promote-btn').forEach(btn => {
        btn.addEventListener('click', handlePromoteClick);
    });
}

async function handlePromoteClick(e) {
    const btn = e.target;
    const userId = btn.dataset.id;
    const userName = btn.dataset.name;

    const errorMsg = document.getElementById('promote-error');
    const successMsg = document.getElementById('promote-success');

    if (!confirm(`Are you sure you want to promote ${userName} to Admin? This gives them full access.`)) {
        return;
    }

    // Optimistic UI update or disabled state
    const originalText = btn.textContent;
    btn.textContent = 'Processing...';
    btn.disabled = true;

    try {
        const response = await fetch(`api/admin/users/promote/${userId}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });

        const result = await response.json();

        if (response.ok) {
            if(successMsg) successMsg.textContent = `${userName} was successfully promoted.`;
            if(errorMsg) errorMsg.textContent = '';
            // Refresh list
            loadCandidates();
        } else {
            if(errorMsg) errorMsg.textContent = result.error?.message || 'Failed to promote.';
            btn.textContent = originalText;
            btn.disabled = false;
        }
    } catch (error) {
        if(errorMsg) errorMsg.textContent = 'Network error occurred.';
        btn.textContent = originalText;
        btn.disabled = false;
    }
}

function escapeHtml(text) {
    if (!text) return '';
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

export function initModalListeners() {
    const modalContainer = document.getElementById('modal-container');
    // Initial triggers (header buttons)
    const initialTriggers = document.querySelectorAll('.modal-trigger');

    if (!modalContainer) return;

    // 1. Define the loader function
    function loadModal(url) {
        fetch(url)
            .then(response => {
                if (!response.ok) throw new Error(`Network response was not ok: ${response.statusText}`);
                return response.text();
            })
            .then(html => {
                // A. Inject HTML
                modalContainer.innerHTML = html;
                const modal = modalContainer.querySelector('.modal');
                const closeModalBtn = modal?.querySelector('.close-modal-btn');
                modal?.classList.remove('hidden');

                // B. Wire Forms
                wireSignupFormInside(modal);
                wireLoginFormInside(modal);
                wireResetFormInside(modal); // <--- NEW: Wire the reset logic

                // C. Wire Internal Triggers (THE FIX)
                // This finds links like "Forgot Password?" inside the newly loaded HTML
                // and attaches the loadModal behavior to them.
                const internalTriggers = modal.querySelectorAll('.modal-trigger');
                internalTriggers.forEach(trigger => {
                    trigger.addEventListener('click', (e) => {
                        e.preventDefault(); // Prevent default link behavior
                        const nextUrl = trigger.dataset.modalUrl;
                        if (nextUrl) loadModal(nextUrl);
                    });
                });

                // D. Close Logic
                const closeModal = () => { modal?.classList.add('hidden'); };
                closeModalBtn?.addEventListener('click', closeModal);
                modal?.addEventListener('click', (event) => { if (event.target === modal) closeModal(); });
            })
            .catch(error => console.error('Error loading modal:', error));
    }

    // 2. Attach to initial buttons (Log In / Sign Up in header)
    if (initialTriggers.length) {
        initialTriggers.forEach(trigger => {
            trigger.addEventListener('click', (e) => {
                e.preventDefault();
                const modalUrl = trigger.dataset.modalUrl;
                if (modalUrl) loadModal(modalUrl);
            });
        });
    }
}

export function wireSignupFormInside(scope) {
    const signupForm = scope?.querySelector?.('#signup-form');
    if (!signupForm) return;

    signupForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        const email = signupForm.querySelector('#email')?.value.trim();
        const password = signupForm.querySelector('#password')?.value.trim();
        const first_name = signupForm.querySelector('#first_name')?.value.trim();
        const last_name = signupForm.querySelector('#last_name')?.value.trim();
        const invitation_key = signupForm.querySelector('#invitation_key')?.value.trim();
        const security_question = signupForm.querySelector('#security_question')?.value;
        const security_answer = signupForm.querySelector('#security_answer')?.value.trim();

        const emailError = signupForm.querySelector('#email-error');
        const passwordError = signupForm.querySelector('#password-error');
        const formError = signupForm.querySelector('#form-error');

        if (emailError) emailError.textContent = '';
        if (passwordError) passwordError.textContent = '';
        if (formError) formError.textContent = '';

        if (!email || !password || !first_name || !last_name || !invitation_key || !security_question || !security_answer) {
            if (formError) formError.textContent = 'Please enter information for all fields.';
            return;
        }

        if (!properEmail(email)) {
            if (emailError) emailError.textContent = 'Invalid email.';
            return;
        }
        if (!properPasswordComplexity(password)) {
            if (passwordError) passwordError.textContent = 'Password must be 8+ chars with uppercase, number, and symbol.';
            return;
        }

        const body = {
            email,
            password,
            first_name,
            last_name,
            invitation_key,
            security_question,
            security_answer
        };

        const result = await handleFormSubmit('signup', body);

        if (result.success) {
            window.location.reload();
        } else {
            if (formError) formError.textContent = result.message;
        }
    });
}


export function wireLoginFormInside(scope) {
    const loginForm = scope?.querySelector?.('#login-form');
    if (!loginForm) return;

    loginForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        const email = loginForm.querySelector('#email')?.value.trim();
        const password = loginForm.querySelector('#password')?.value.trim();

        const formError = loginForm.querySelector('#form-error');

        formError.textContent = '';

        if (!email || !password ) {
            formError.textContent = 'Please enter information for all fields.';
            return;
        }

        const body = {email, password};
        const result = await handleFormSubmit('login', body);
        if (result.success) {
            window.location.reload();
        } else {
            formError.textContent = result.message;
        }
    });
}

export function wireResetFormInside(scope) {
    const requestForm = scope?.querySelector('#reset-request-form');
    const confirmForm = scope?.querySelector('#reset-confirm-form');

    // Step 1: Request Question
    if (requestForm) {
        requestForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = requestForm.querySelector('#reset-email').value.trim();
            const errorSpan = requestForm.querySelector('#reset-request-error');
            errorSpan.textContent = '';

            if(!properEmail(email)) {
                errorSpan.textContent = "Invalid email format.";
                return;
            }

            try {
                const response = await fetch('reset-request', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email })
                });
                const data = await response.json();

                if (response.ok) {
                    // Hide Step 1, Show Step 2
                    requestForm.classList.add('hidden');
                    confirmForm.classList.remove('hidden');
                    scope.querySelector('#security-question-display').textContent = data.data.question;
                    // Pass the email to the second form implicitly or via hidden field,
                    // or just read it from the first input since it's still in the DOM
                } else {
                    errorSpan.textContent = data.message || "Account not found.";
                }
            } catch (err) {
                errorSpan.textContent = "Network error.";
            }
        });
    }

    // Step 2: Confirm Reset
    if (confirmForm) {
        confirmForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = requestForm.querySelector('#reset-email').value.trim(); // Get from Step 1 input
            const answer = confirmForm.querySelector('#reset-answer').value.trim();
            const newPassword = confirmForm.querySelector('#new-password').value.trim();
            const errorSpan = confirmForm.querySelector('#reset-confirm-error');
            errorSpan.textContent = '';

            if (!properPasswordComplexity(newPassword)) {
                errorSpan.textContent = "Password too weak.";
                return;
            }

            const body = {
                email: email,
                security_answer: answer,
                new_password: newPassword
            };

            const result = await handleFormSubmit('reset-confirm', body);
            if (result.success) {
                alert("Password reset successful. Please log in.");
                // Reload to clear modals and let user log in
                window.location.reload();
            } else {
                errorSpan.textContent = result.message;
            }
        });
    }
}

async function handleFormSubmit(endpoint, body) {
    try {
        const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });

        const data = await response.json();

        if (response.ok) {
            return {success: true};
        } else {
            return {
                success: false,
                message: `Error: ${data.error.code}, ${data.error.message}`
            };
        }
    } catch (error) {
        return {
            success: false,
            message: `Unexpected Error: ${error}`
        };
    }
}

export function properEmail(email) {
  const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  return emailRegex.test(email);
}
export function properPasswordComplexity(password) {
  const strongPasswordRegex = /^(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).{8,}$/;
  return strongPasswordRegex.test(password);
}