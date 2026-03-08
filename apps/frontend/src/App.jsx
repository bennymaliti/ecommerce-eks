import React, { useEffect, useState } from 'react'

function App() {
  const [products, setProducts] = useState([])
  const [status, setStatus] = useState('Checking...')

  useEffect(() => {
    fetch('/api/products')
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then(data => {
        setProducts(Array.isArray(data) ? data : [])
        setStatus('‚úÖ Connected')
      })
      .catch(() => {
        setStatus('‚ö†Ô∏è API Unavailable')
        setProducts([])
      })
  }, [])

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1>Ìªí ECommerce Store</h1>
      <p>API Status: <strong>{status}</strong></p>
      <h2>Products</h2>
      {products.length === 0 ? (
        <p>No products available</p>
      ) : (
        <ul>
          {products.map(p => (
            <li key={p.id}>{p.name} ‚Äî ¬£{p.price}</li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default App
