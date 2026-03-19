import React from "react";

const steps = [
  { number: "1", title: "Create a Character", text: "Pick a race, class, and abilities. The sheet handles the math so you can focus on the story." },
  { number: "2", title: "Choose an Adventure", text: "Browse hand-crafted story hooks or let the AI weave a tale around your character." },
  { number: "3", title: "Play", text: "Make choices, roll dice, and watch the narrative unfold — all in real time from your browser." },
];

const HowItWorks: React.FC = () => (
  <section className="fp-how">
    <h2 className="fp-how__heading">How It Works</h2>
    <div className="fp-how__steps">
      {steps.map((s) => (
        <div key={s.number} className="fp-how__step">
          <span className="fp-how__number">{s.number}</span>
          <h3>{s.title}</h3>
          <p>{s.text}</p>
        </div>
      ))}
    </div>
  </section>
);

export default HowItWorks;
