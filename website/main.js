function handleWaitlist(e) {
  e.preventDefault();
  const email = document.getElementById("email").value;
  const msg = document.getElementById("waitlist-msg");
  // Replace with Formspree/ConvertKit/Postmark when ready.
  msg.textContent = `Thanks — we'll reach out at ${email} when cloud is ready.`;
  msg.style.color = "#22d3ee";
  return false;
}