import React from "react";

interface Feature {
  image: string;
  title: string;
  description: string;
}

const features: Feature[] = [
  {
    image: "/images/frontpage/feature-sheets.jpg",
    title: "Character Sheets",
    description:
      "Create and manage detailed character sheets with automatic stat calculations, skill tracking, and spell management. Point-buy, feats, equipment — it's all here.",
  },
  {
    image: "/images/frontpage/feature-adventure.jpg",
    title: "Living Adventures",
    description:
      "Dive into AI-driven adventures that respond to your choices. Every decision shapes the story, every roll matters. Your campaign, your way.",
  },
  {
    image: "/images/frontpage/feature-play.jpg",
    title: "Play Anywhere",
    description:
      "No scheduling hassles, no table required. Jump into a session from your browser whenever the mood strikes. Your characters are always ready.",
  },
];

const Features: React.FC = () => (
  <section className="fp-features">
    <h2 className="fp-features__heading">Everything You Need to Play</h2>
    <div className="fp-features__grid">
      {features.map((f) => (
        <div key={f.title} className="fp-feature-card">
          <div className="fp-feature-card__img-wrap">
            <img src={f.image} alt={f.title} loading="lazy" />
          </div>
          <h3 className="fp-feature-card__title">{f.title}</h3>
          <p className="fp-feature-card__desc">{f.description}</p>
        </div>
      ))}
    </div>
  </section>
);

export default Features;
