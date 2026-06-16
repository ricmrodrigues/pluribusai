async function handleWaitlist(e) {
  e.preventDefault();
  const form = e.target;
  const msg = document.getElementById("waitlist-msg");
  const btn = form.querySelector('button[type="submit"]');
  const originalText = btn.textContent;

  btn.disabled = true;
  btn.textContent = "Joining…";
  msg.textContent = "";
  msg.style.color = "";

  try {
    const response = await fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      headers: { Accept: "application/json" },
    });

    if (response.ok) {
      const email = document.getElementById("email").value;
      msg.textContent = `Thanks — we'll reach out at ${email} when cloud is ready.`;
      msg.style.color = "#22d3ee";
      form.reset();
    } else {
      const data = await response.json().catch(() => ({}));
      msg.textContent = data.error || "Something went wrong. Try again?";
      msg.style.color = "#f87171";
    }
  } catch {
    msg.textContent = "Network error. Try again?";
    msg.style.color = "#f87171";
  } finally {
    btn.disabled = false;
    btn.textContent = originalText;
  }

  return false;
}