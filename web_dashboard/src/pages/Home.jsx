import FeatureGrid from '../components/FeatureGrid.jsx'

export default function Home() {
  return (
    <>
      <section className="hero">
        <h1>Every clip knows where it came from.</h1>
        <p>
          Binnacle Connect pairs with Vision to track riders, save highlights, and
          keep everyone on the boat in the loop — without anyone touching a camera.
        </p>
        <button className="cta">Get the app</button>
      </section>
      <FeatureGrid />
      <p className="footnote">
        This site is a UX/architecture prototype (Connect_Master_Design_and_Build_Spec).
        Vision hardware has not been built yet — features described here are the
        product design, not a shipped capability.
      </p>
    </>
  )
}
