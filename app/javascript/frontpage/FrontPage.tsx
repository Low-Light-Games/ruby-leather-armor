import React from "react";
import "./FrontPage.scss";

const FrontPage: React.FC = () => (
  <div className="fp">
    <header className="fp-header">
      <div className="fp-header__inner">
        <h1 className="fp-header__title">Leather Armor</h1>
        <p className="fp-header__tagline">The Dungeon Does Not Care</p>
        <hr className="fp-header__rule" />
        <p className="fp-typewriter fp-header__subtitle">
          An AI-Refereed Solo Adventure System
          <br />
          for the Pathfinder<sup><a href="#paizo-note" className="fp-header__footnote-ref">*</a></sup> Roleplaying Game
        </p>
      </div>
    </header>

    <div className="fp-illustration">
      <div className="fp-illustration__frame">
        <img
          src="/images/frontpage/hero-dungeon.jpg"
          alt="A dark dungeon corridor lit by flickering torches"
          className="fp-illustration__img"
        />
      </div>
      <p className="fp-illustration__caption">
        Fig. 1. — The corridor ahead. You have a torch. It will not last.
      </p>
    </div>

    <main className="fp-main">

      <section className="fp-section">
        <h2 className="fp-section__heading">Foreword</h2>
        <p>
          What you have before you is not a game in the modern sense. There are no
          tutorials. There is no scaling difficulty. The system presented here uses a
          large language model — an artificial intelligence, if we are to be generous
          with that term — to serve as your referee, adversary, and narrator in solo
          adventures through procedurally-generated dungeons and wildernesses.
        </p>
        <p>
          The AI operates within the Pathfinder<sup><a href="#paizo-note" className="fp-header__footnote-ref">*</a></sup> rules system. It rolls dice. It
          tracks your hit points, your rations, your torches. It does not fudge
          results. When you fail a save against poison, you are poisoned. When you
          fall in combat, you may die. This is the intended experience.
        </p>
        <p>
          The philosophy owes more to the original tabletop tradition — to{" "}
          <em>Chainmail</em>, to the earliest dungeon crawls of the 1970s — than to
          the modern notion that the player character is a hero on a predetermined
          journey. Here, you are an adventurer. That word used to mean something more
          desperate than it does now.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">On the Limitations of the Machine Referee</h2>
        <p>
          It would be dishonest not to address this plainly. The AI that runs your
          game is a language model. It is not intelligent. It does not understand the
          rules the way a human game master does — it approximates them, often
          convincingly, sometimes not. There will be moments where it loses track of
          a detail, applies a rule incorrectly, or generates a response that doesn't
          quite follow from what came before.
        </p>
        <p>
          We have worked to constrain it: to give it structure, to ground it in the
          actual rules text, to make it track state with reasonable fidelity. But we
          will not pretend it is something it is not. A language model is a
          sophisticated text predictor. It can maintain a surprisingly engaging
          adventure — and it can also, on occasion, hallucinate a door in a wall
          that wasn't there, or forget that you already searched the chest.
        </p>
        <p>
          If you have played tabletop games with a distracted or novice game master,
          you will find the experience familiar. The difference is that the AI never
          tires, never cancels the session, and is available at three in the morning
          when you cannot sleep and want to see what's on the second level of the
          tomb.
        </p>
        <p>We consider this an honest trade.</p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">On the Nature of the Adventures</h2>
        <p>
          The tone is grim. Not gratuitously so — we are not interested in shock for
          its own sake — but the world generated here treats the player character as
          a mortal creature in a hostile environment. Resources are finite. Rest is
          dangerous. The things in the dark are not calibrated to your level.
        </p>
        <p>
          You will die. Probably often, at first. A first-level character with
          eight hit points and a shortbow does not have plot armor. The AI will
          describe your death with the same matter-of-fact prose it uses for
          everything else. You may roll a new character and try again.
        </p>
        <p>
          The reward for survival is not a cinematic ending. It is the accumulation
          of small, hard-won gains: a map of the upper level, a magic weapon you
          don't fully understand, enough gold to buy better armor. The stories that
          emerge are your own. They are better for not having been scripted.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section">
        <h2 className="fp-section__heading">On Playing Alone</h2>
        <p>
          Solo play has always existed at the margins of the hobby. There have been
          paragraph-books, oracle systems, and procedural generators of varying
          quality. What a language model offers — imperfect as it is — is something
          closer to the feel of having another person across the table. Not identical
          to it. But closer than anything before.
        </p>
        <p>
          You type what your character does. The AI tells you what happens. Sometimes
          it asks what you'd like to do. Sometimes it simply tells you that the floor
          has given way and you are now thirty feet below where you were, and you
          should probably check if your legs still work.
        </p>
      </section>

      <hr className="fp-divider" />

      <section className="fp-section fp-section--closing">
        <p>
          If any of the above appeals to you — and if you understand that what is
          offered is an imperfect, interesting, sometimes frustrating, often
          surprising thing — then you are welcome at the table.
        </p>
        <div className="fp-cta-wrap">
          <a href={(window as any).AppUrl} className="fp-cta-btn">
            Begin
          </a>
        </div>
        <p className="fp-typewriter fp-closing-note">
          Bring torches. Bring rope. Bring a ten-foot pole.
          <br />
          You will need all of them.
        </p>
      </section>

    </main>

    <footer className="fp-footer">
      <nav className="fp-footer__links">
        <a href="/legal" className="fp-typewriter fp-footer__link">Open Game License</a>
        <a href="/privacy" className="fp-typewriter fp-footer__link">Privacy</a>
      </nav>
      <p className="fp-typewriter fp-footer__copy">&copy; {new Date().getFullYear()} leatherarmor.io</p>
      <p id="paizo-note" className="fp-typewriter fp-footer__disclaimer">
        * Not affiliated with, endorsed by, or connected to{" "}
        <a href="https://paizo.com" target="_blank" rel="noopener noreferrer" className="fp-footer__disclaimer-link">Paizo Inc.</a>
        {" "}Pathfinder is a registered trademark of Paizo Inc.
      </p>
    </footer>
  </div>
);

export default FrontPage;
