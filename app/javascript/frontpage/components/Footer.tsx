import React from "react";

const Footer: React.FC = () => (
  <footer className="fp-footer">
    <div className="fp-footer__inner">
      <p className="fp-footer__brand">Leather Armor</p>
      <nav className="fp-footer__links">
        <a href="/legal">Open Game License</a>
        <a href="/sheets">Character Sheets</a>
        <a href="/adventures">Adventures</a>
      </nav>
      <p className="fp-footer__copy">&copy; {new Date().getFullYear()} leatherarmor.io</p>
    </div>
  </footer>
);

export default Footer;
