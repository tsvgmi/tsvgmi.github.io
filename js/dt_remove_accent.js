$(function() {
  function removeAccents ( data ) {
    return data
      .replace( /[aáàảãạâấầẩẫậăắằẳẵặ]/g, 'a' )
      .replace( /[AÁÀẢÃẠÂẤẦẨẪẬĂẮẰẲẴẶ]/g, 'A' )
      .replace( /đ/g, 'd' )
      .replace( /Đ/g, 'D' )             
      .replace( /[éèẻẽẹêếềểễệ]/g, 'e' )
      .replace( /[ÉÈẺẼẸÊẾỀỂỄỆ]/g, 'E' )	  
      .replace( /[íìỉĩị]/g, 'i' )
      .replace( /[ÍÌỈĨỊ]/g, 'I' )          
      .replace( /[óòỏõọôốồổỗộơớờởỡợ]/g, 'o' )
      .replace( /[ÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢ]/g, 'O' )
      .replace( /[úùủũụưứừửữự]/g, 'u' )
      .replace( /[ÙUỦŨỤƯỨỪỬỮỰ]/g, 'U' )
      .replace( /[ýỳỷỹỵ]/g, 'y' )
      .replace( /[ÝỲỶỸỴ]/g, 'Y' )
      ;
  }

  var searchType = jQuery.fn.DataTable.ext.type.search;
   
  searchType.string = function ( data ) {
	var repstr = ! data ?
          '' :
          typeof data === 'string' ?
              removeAccents( data ) :
              data;
	//console.log(repstr)
	return repstr;
  };
   
  searchType.html = function ( data ) {
     var repstr = ! data ?
          '' :
          typeof data === 'string' ?
              removeAccents( data.replace( /<.*?>/g, '' ) ) :
              data;
	//console.log(repstr)
	return repstr;			 
  };
});
