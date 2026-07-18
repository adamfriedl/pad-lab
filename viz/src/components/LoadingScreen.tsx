export function LoadingScreen() {
  return (
    <div className='shell state loading-screen'>
      <div className='atmosphere' aria-hidden='true' />
      <div
        className='loading-card'
        role='status'
        aria-live='polite'
        aria-label='Loading mart snapshots'
      >
        <div className='loading-ring' aria-hidden='true'>
          <span className='loading-ring-track' />
          <span className='loading-ring-arc' />
        </div>
        <p className='loading-label'>Loading mart snapshots</p>
        <div className='loading-dots' aria-hidden='true'>
          <span />
          <span />
          <span />
        </div>
      </div>
    </div>
  );
}
