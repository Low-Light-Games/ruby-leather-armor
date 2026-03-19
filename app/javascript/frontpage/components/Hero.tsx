import React from "react";

const Hero: React.FC = () => (
  <section
    className="fp-hero"
    style={{ backgroundImage: 'url("/images/frontpage/hero.jpg")' }}
  >
    <div className="fp-hero__overlay" />
    <div className="fp-hero__content">
      <h1 className="fp-hero__title">Your Adventure Awaits</h1>
      <p className="fp-hero__subtitle">
        Build characters, forge stories, and play epic tabletop campaigns — all
        in one place.
      </p>
      <div className="fp-hero__actions">
        <a href="/sheets" className="fp-btn fp-btn--primary">
          Create a Character
        </a>
        <a href="/adventures" className="fp-btn fp-btn--secondary">
          Browse Adventures
        </a>
      </div>
    </div>
  </section>
);

export default Hero;
